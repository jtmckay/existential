#!/usr/bin/env bash
# fleet — set a host up as the controller or as a worker on your own network, in one command.
#   ./existential.sh run fleet controller            on the controller: prints the join command
#   ./existential.sh run fleet join <controller> [<secret>]   on every other host
#   ./existential.sh run fleet api                   a GPU box's lease API, hosting/fleet-api, on :8801
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

# The address the others reach this host by, as report_host offers it.
address() {
    local a; a="$(env_get "$ENV" EXIST_TAILNET_NAME)"
    [[ -n "$a" ]] || a="$(env_get "$ENV" EXIST_LOCAL_HOST_IP)"
    echo "${a:-$(hostname)}"
}

# The host daemon runs the host plugins (report_host, pull_existential, lease_gpu): started now
# and at every boot (host-daemon.sh install), whatever already runs.
start_daemon() {
    bash "${SCRIPT_DIR}/host-daemon.sh" install || echo "  daemon   not started (above); then: ./existential.sh run host-daemon install"
}

# A GPU box's lease API: hosting/fleet-api, decree-go-rest pulled as an image and run by
# Compose (restart: unless-stopped, so it comes back with the engine), in front of this host's
# .decree on the LAN at :8801 behind the fleet secret. lease_gpu, a host plugin in this host's
# decree daemon, does the leasing, so a GPU box is a worker by choice. The controller never runs
# it: its API is the model gateway. A box set up before this started decree-go-rest from
# .decree/boot.sh in tmux: that line, session and container go.
cmd_api() {
    local boot="${REPO_DIR}/.decree/boot.sh" engine t
    engine="$(command -v podman || command -v docker || true)"
    [[ -n "$engine" ]] || die "the lease API runs in a container: install podman or docker"
    if grep -q 'decree-go-rest' "$boot" 2>/dev/null; then
        t="$(mktemp)"; grep -v 'decree-go-rest' "$boot" > "$t" || true; cat "$t" > "$boot"; rm -f "$t"
        tmux kill-session -t "=decree-go-rest" 2>/dev/null || true
        "$engine" rm -f decree-go-rest >/dev/null 2>&1 || true
        echo "  api      took the old decree-go-rest out of .decree/boot.sh"
    fi
    exist service on fleet-api
    ( cd "$REPO_DIR" && "$engine" compose up -d fleet-api )
    echo "  api      http://$(address):8801 (docker logs fleet-api), back after every reboot with the engine"
}

cmd_controller() {
    [[ -f "$ENV" ]] || die "run ./existential.sh first"
    echo "This host is the controller:"
    env_set "$ENV" EXIST_CONTROLLER ""
    local secret; secret="$(env_get "$ENV" EXIST_FLEET_SECRET)"
    if [[ -z "$secret" ]]; then
        secret="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
        env_set "$ENV" EXIST_FLEET_SECRET "$secret"
        echo "  secret   made"
    fi
    # Containers only: where the reports land (Loki, Grafana) and the fleet's API (the model
    # gateway). Nothing on the host itself: this host reports itself only if it is also made a
    # worker, by choice (./existential.sh plugin on report_host).
    exist service on loki grafana model-gateway
    # Loki on the network, so the workers can push to it and ask it who the controller is.
    env_set "$LOKI_ENV" LOKI_BIND 0.0.0.0
    echo "  loki     on the network at :43100"
    echo ""
    echo "Start Loki, Grafana and the model gateway:  docker compose up -d"
    echo "Then on every other host:"
    echo "  ./existential.sh run fleet join $(address) ${secret}"
    echo "and, to code against the fleet's GPUs, in its .env.shared:  EXIST_MODEL_URL=http://$(address):4400/v1"
    echo "And in a decree project of your own, with EXIST_CONTROLLER=$(address) and EXIST_FLEET_SECRET in its .decree/.env:"
    echo "  set -a; . .decree/.env; set +a; curl -fsSL -H \"Authorization: Bearer \$EXIST_FLEET_SECRET\" \"http://\$EXIST_CONTROLLER:4400/plugins/fleet_gpu.md\" | decree install -"
}

cmd_join() {
    local ctl="${1:-}" secret="${2:-}"
    [[ "$ctl" =~ ^[A-Za-z0-9.-]+$ ]] || die "usage: fleet join <controller's address> [<secret>]"
    [[ -f "$ENV" ]] || die "run ./existential.sh first, then this again"
    if [[ -z "$secret" && -t 0 ]]; then
        read -r -s -p "Fleet secret (from the controller's fleet controller): " secret; echo ""
    fi
    echo "This host reports to ${ctl}:"
    env_set "$ENV" EXIST_CONTROLLER "$ctl"
    [[ -z "$secret" ]] || env_set "$ENV" EXIST_FLEET_SECRET "$secret"
    exist plugin on report_host
    exist
    start_daemon
    # The lease API takes the secret only when it starts: recreate it with the new one.
    if grep -q '^EXIST_IS_HOSTING_FLEET_API=true' "$ENV"; then
        ( cd "$REPO_DIR" && "$(command -v podman || command -v docker)" compose up -d fleet-api )
    fi
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
    # The host daemon and its reports are a worker's (report_host), never set up for a controller.
    grep -qxF report_host "${REPO_DIR}/.decree/plugins/.on" 2>/dev/null || { echo "  reports     none from this host (a worker's: plugin on report_host)"; return 0; }
    if tmux has-session -t "=existential-host" 2>/dev/null; then echo "  daemon      running"; else echo "  daemon      NOT RUNNING (./existential.sh run host-daemon install)"; fi
    runs="${REPO_DIR}/.decree/runs"
    for r in $(ls -t "$runs" 2>/dev/null | head -n 20); do
        last="$(grep -m1 '^reporting:' "${runs}/${r}/0001-report.log" 2>/dev/null)" && break
    done
    last="${last#reporting: }"; echo "  last report ${last:-none yet (the first is within 5 minutes)}"
}

case "${1:-status}" in
    controller) cmd_controller ;;
    api)        cmd_api ;;
    join)       shift; cmd_join "$@" ;;
    status)     cmd_status ;;
    *)          die "usage: fleet controller | fleet join <controller> [<secret>] | fleet api | fleet status" ;;
esac
