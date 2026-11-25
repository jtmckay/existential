#!/usr/bin/env bash
# peers — what the other hosts offer, asked of the controller: every host's report_host pushes
# its offers (kind=offer) to the Loki the controller names, and this reads the latest of each.
#   ./existential.sh run peers [<service>] [--json]     every host's offers, or one service's
#   ./existential.sh run peers lease <host> <service> <client>
#                                   ask that host for its card, wait until it is held, print the id
#   ./existential.sh run peers release <host> <service> <id>   give the lease back
# A lease needs EXIST_FLEET_SECRET in .env.shared, the same on every host.
#
# The same code as the stack's decree scripts: the fleet lib (automation/plugins/flows/fleet.md).
# Runs on the host, a Mac included: bash 3.2. Needs curl, jq and yq.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
die() { echo "peers: $*" >&2; exit 1; }
for t in curl jq yq; do command -v "$t" >/dev/null 2>&1 || die "needs ${t} on this host"; done
env_get() { grep -E "^$1=" "${REPO_DIR}/.env.shared" 2>/dev/null | head -1 | cut -d= -f2-; }

lib="$(mktemp)"; trap 'rm -f "$lib"' EXIT
yq --front-matter=extract -r '.["x-exist-lib"]["fleet.sh"]' "${REPO_DIR}/automation/plugins/flows/fleet.md" > "$lib"
# shellcheck source=/dev/null
. "$lib"

# The Loki the controller names: asked fresh when this host has one, else its last answer;
# the controller reads its own. Then what reporting last used.
loki_url() {
    local ctl ans="" f
    ctl="$(env_get EXIST_CONTROLLER)"
    [[ -z "$ctl" ]] || ans="$(curl -fsS --max-time 5 "http://${ctl}:4480/" 2>/dev/null || true)"
    for f in "${REPO_DIR}/.decree/controller.json" "${REPO_DIR}/.decree/exist.json"; do
        [[ -n "$ans" ]] || ans="$(cat "$f" 2>/dev/null || true)"
    done
    ans="$(jq -r '.loki // empty' <<<"$ans" 2>/dev/null || true)"
    [[ -n "$ans" ]] || ans="$(cat "${REPO_DIR}/.decree/machines/report_host/state/loki" 2>/dev/null || true)"
    [[ -n "$ans" ]] || die "no Loki named: turn on the report-host flow, and set EXIST_CONTROLLER (blank on the controller)"
    echo "$ans"
}
EXIST_FLEET_LOKI="$(loki_url)"
EXIST_FLEET_SECRET="$(env_get EXIST_FLEET_SECRET)"

# The one offer of <service> by <host>, or fail.
offer_of() {
    local o
    o="$(fleet_offers "$2" | jq -c --arg h "$1" 'select(.host == $h)' | head -n 1)"
    [[ -n "$o" ]] || die "${1} offers no ${2} (./existential.sh run peers)"
    [[ -n "$(jq -r '.lease // empty' <<<"$o")" ]] || die "${1}'s ${2} takes no lease"
    [[ -n "$EXIST_FLEET_SECRET" ]] || die "set EXIST_FLEET_SECRET in .env.shared, the same on every host"
    echo "$o"
}

case "${1:-}" in
    lease)
        [[ $# -eq 4 ]] || die "usage: peers lease <host> <service> <client>"
        fleet_lease "$(offer_of "$2" "$3")" "$4" || die "${2} did not lease its ${3}" ;;
    release)
        [[ $# -eq 4 ]] || die "usage: peers release <host> <service> <id>"
        fleet_answer "$(offer_of "$2" "$3")" "$4" release || die "${2} did not take the release"
        echo "peers: released ${4} on ${2}" ;;
    *)
        json=false svc=""
        for a in "$@"; do if [[ "$a" == --json ]]; then json=true; else svc="$a"; fi; done
        all="$(fleet_offers "$svc")" || die "the Loki at ${EXIST_FLEET_LOKI} did not answer"
        if $json; then jq -s -c . <<<"$all"; exit 0; fi
        [[ -n "$all" ]] || { echo "No host offers ${svc:-anything} (reports from the last 15 minutes)."; exit 0; }
        jq -r '[.host, .service, .url, (if .lease then "lease " + .lease + "/<client>"
            elif .start then "start " + .start else "-" end)] | @tsv' <<<"$all" |
            while IFS=$'\t' read -r h s u how; do printf '%-16s %-8s %-40s %s\n' "$h" "$s" "$u" "$how"; done ;;
esac
