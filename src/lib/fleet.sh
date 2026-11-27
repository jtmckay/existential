#!/usr/bin/env bash
# fleet — set a host up as the controller or as a worker on your own network, in one command.
#   ./existential.sh run fleet controller            on the controller: prints the join command
#   ./existential.sh run fleet join <controller's domain> [<secret>]   on every other host
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
# it: its API is the model gateway.
cmd_api() {
    local engine
    engine="$(command -v podman || command -v docker || true)"
    [[ -n "$engine" ]] || die "the lease API runs in a container: install podman or docker"
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
    # Containers only: where the reports land (Loki, Grafana), the fleet's API (the model
    # gateway) and Caddy, the one way in: every other host reaches it over HTTPS, as
    # https://model-gateway.<domain> (models, and Loki's paths), which takes the fleet secret.
    # Loki itself stays on loopback (it has no login). Nothing on the host itself: this host
    # reports itself only if it is also made a worker, by choice (./existential.sh plugin on report_host).
    exist service on loki grafana model-gateway caddy
    local domain; domain="$(env_get "$ENV" EXIST_DOMAIN)"
    echo "  loki     reached by the workers at https://model-gateway.${domain}, with the secret"
    echo ""
    echo "Start Loki, Grafana, the model gateway and Caddy:  docker compose up -d"
    # Caddy's own CA signed its certificate (no certificate of yours in hosting/caddy/certs):
    # every worker must trust it, or no report gets through.
    if openssl verify -CAfile "${REPO_DIR}/hosting/caddy/certs/internal-ca.pem" "${REPO_DIR}/hosting/caddy/certs/internal.pem" >/dev/null 2>&1; then
        echo "⚠  Caddy's certificate is signed by this host's own CA: install hosting/caddy/certs/internal-ca.pem"
        echo "   on every worker first (docs: Controller and Workers), or use a certificate of your own."
    fi
    if ! grep -qxF report_host "${REPO_DIR}/.decree/plugins/.on" 2>/dev/null; then
        echo "Recommended, to report this host too and relay the others' notifications (runs on the host):"
        echo "  ./existential.sh plugin on report_host && ./existential.sh run host-daemon install"
    fi
    echo "Then on every other host:"
    echo "  ./existential.sh run fleet join ${domain} ${secret}"
    echo "and, to code against the fleet's GPUs, in its .env.shared:  EXIST_MODEL_URL=https://model-gateway.${domain}/v1"
    echo "And in a decree project of your own, with EXIST_CONTROLLER=${domain} and EXIST_FLEET_SECRET in its .decree/.env:"
    echo "  set -a; . .decree/.env; set +a; curl -fsSL -H \"Authorization: Bearer \$EXIST_FLEET_SECRET\" \"https://model-gateway.\$EXIST_CONTROLLER/plugins/fleet_gpu.md\" | decree install -"
}

cmd_join() {
    local ctl="${1:-}" secret="${2:-}"
    [[ "$ctl" =~ ^[A-Za-z0-9.-]+$ && ! "$ctl" =~ ^[0-9.]+$ ]] || die "usage: fleet join <controller's domain, its EXIST_DOMAIN> [<secret>]"
    [[ -f "$ENV" ]] || die "run ./existential.sh first, then this again"
    if [[ -z "$secret" && -t 0 ]]; then
        read -r -s -p "Fleet secret (from the controller's fleet controller): " secret; echo ""
    fi
    echo "This host reports to https://model-gateway.${ctl}:"
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
            echo "  role        controller (Loki bind: $(env_get "$LOKI_ENV" LOKI_BIND); the workers reach it at https://model-gateway.$(env_get "$ENV" EXIST_DOMAIN))"
        else
            echo "  role        NONE: no EXIST_CONTROLLER and no Loki here (fleet join <controller>)"
        fi
    elif printf 'Authorization: Bearer %s\n' "$secret" | curl -fsS --max-time 5 -H @- "https://model-gateway.${ctl}/loki/api/v1/labels" >/dev/null 2>&1; then
        echo "  role        worker of ${ctl} (https://model-gateway.${ctl} answers)"
    else
        echo "  role        worker of ${ctl} (NO ANSWER at https://model-gateway.${ctl} with this secret)"
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
