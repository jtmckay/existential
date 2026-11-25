#!/usr/bin/env bash
# fleet — set a host up as the controller or as a worker on your own network, in one command.
#   ./existential.sh run fleet controller            on the controller: prints the join command
#   ./existential.sh run fleet join <controller> [<secret>]   on every other host
#   ./existential.sh run fleet status                what this host has, and what it can reach
# Each step is what site/docs/hosting/controller-and-workers.md does by hand; running one twice
# changes nothing. Runs on the host, a Mac included: bash 3.2, BSD tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV="${REPO_DIR}/.env.shared"
LOKI_ENV="${REPO_DIR}/hosting/loki/.env"
die() { echo "fleet: $*" >&2; exit 1; }
exist() { "${REPO_DIR}/existential.sh" "$@"; }

env_get() { grep -E "^$2=" "$1" 2>/dev/null | head -n 1 | cut -d= -f2- || true; }
env_set() {  # <file> <key> <value>: the first line for key, or a new one
    local t; t="$(mktemp)"
    if grep -qE "^$2=" "$1" 2>/dev/null; then
        awk -v k="$2" -v v="$3" 'index($0, k "=") == 1 && !d { print k "=" v; d = 1; next } { print }' "$1" > "$t"
    else
        { cat "$1" 2>/dev/null || true; echo "$2=$3"; } > "$t"
    fi
    cat "$t" > "$1"; rm -f "$t"
}

# The address the others reach this host by, as reporting offers it.
address() {
    local a; a="$(env_get "$ENV" EXIST_TAILNET_NAME)"
    [[ -n "$a" ]] || a="$(env_get "$ENV" EXIST_LOCAL_HOST_IP)"
    echo "${a:-$(hostname)}"
}

# The host daemon runs the worker flow (reporting, update, ai-box): started here when it isn't.
start_daemon() {
    if tmux has-session -t "=existential-host" 2>/dev/null; then echo "  daemon   running (tmux existential-host)"; return 0; fi
    command -v decree >/dev/null 2>&1 || { echo "  daemon   not started: install decree (./existential.sh says how), then rerun"; return 0; }
    tmux new -d -s existential-host -c "$REPO_DIR" decree daemon
    echo "  daemon   started (tmux existential-host); have it start at boot: site/docs/hosting/host-daemon.md"
}

cmd_controller() {
    [[ -f "$ENV" ]] || die "run ./existential.sh first (pick Controller)"
    echo "This host is the controller:"
    env_set "$ENV" EXIST_CONTROLLER ""
    local secret; secret="$(env_get "$ENV" EXIST_FLEET_SECRET)"
    if [[ -z "$secret" ]]; then
        secret="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
        env_set "$ENV" EXIST_FLEET_SECRET "$secret"
        echo "  secret   made"
    fi
    exist flow on worker
    exist service on loki grafana
    # Loki on the network, so the workers can push to it and ask it who the controller is.
    env_set "$LOKI_ENV" LOKI_BIND 0.0.0.0
    exist
    echo "  loki     on the network at :43100"
    start_daemon
    echo ""
    echo "Start Loki and Grafana:  docker compose up -d"
    echo "Then on every other host:"
    echo "  ./existential.sh run fleet join $(address) ${secret}"
}

cmd_join() {
    local ctl="${1:-}" secret="${2:-}"
    [[ "$ctl" =~ ^[A-Za-z0-9.-]+$ ]] || die "usage: fleet join <controller's address> [<secret>]"
    [[ -f "$ENV" ]] || die "run ./existential.sh first (pick Worker), then this again"
    if [[ -z "$secret" && -t 0 ]]; then
        read -r -s -p "Fleet secret (from the controller's fleet controller): " secret; echo ""
    fi
    echo "This host reports to ${ctl}:"
    env_set "$ENV" EXIST_CONTROLLER "$ctl"
    [[ -z "$secret" ]] || env_set "$ENV" EXIST_FLEET_SECRET "$secret"
    exist flow on worker
    exist
    start_daemon
    echo ""
    cmd_status
}

cmd_status() {
    [[ -f "$ENV" ]] || die "run ./existential.sh first"
    local ctl secret runs r last=""
    ctl="$(env_get "$ENV" EXIST_CONTROLLER)"
    secret="$(env_get "$ENV" EXIST_FLEET_SECRET)"
    if [[ -z "$ctl" ]]; then
        if grep -q '^EXIST_IS_HOSTING_LOKI=true' "$ENV"; then
            echo "  role        controller (Loki bind: $(env_get "$LOKI_ENV" LOKI_BIND))"
        else
            echo "  role        NONE: no EXIST_CONTROLLER and no Loki here (fleet join <controller>)"
        fi
    elif curl -fsS --max-time 5 "http://${ctl}:4480/" >/dev/null 2>&1 ||
        curl -fsS --max-time 5 "http://${ctl}:43100/loki/api/v1/labels" >/dev/null 2>&1; then
        echo "  role        worker of ${ctl} (it answers)"
    else
        echo "  role        worker of ${ctl} (NO ANSWER on :4480 or :43100)"
    fi
    echo "  address     $(address)"
    if [[ -n "$secret" ]]; then echo "  secret      set, starts ${secret:0:6}"; else echo "  secret      NOT SET: leases off"; fi
    if tmux has-session -t "=existential-host" 2>/dev/null; then echo "  daemon      running"; else echo "  daemon      NOT RUNNING"; fi
    runs="${REPO_DIR}/.decree/runs"
    for r in $(ls -t "$runs" 2>/dev/null | head -n 20); do
        last="$(grep -m1 '^reporting:' "${runs}/${r}/0001-report.log" 2>/dev/null)" && break
    done
    last="${last#reporting: }"; echo "  last report ${last:-none yet (the first is within 5 minutes)}"
}

case "${1:-status}" in
    controller) cmd_controller ;;
    join)       shift; cmd_join "$@" ;;
    status)     cmd_status ;;
    *)          die "usage: fleet controller | fleet join <controller> [<secret>] | fleet status" ;;
esac
