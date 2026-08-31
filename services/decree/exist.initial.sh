#!/usr/bin/env bash
# decree — pre-startup init: activate the triage cron.
#
# Runs on the host (and in adhoc — it is a plain file copy inside the repo).
# Called every `./existential.sh` for an enabled decree; skips silently once the
# active copy exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# triage is `enabled: true` in config.exist.yml and deliberately not opt-in — a
# stack nobody is watching is exactly the one that needs it. But cron/ is
# gitignored (it is the user's active set), so the tracked example is the only
# copy in git and the routine never ticks until something puts it in place. No
# quest owns this: 18 quests can enable decree, and triage has to work from all
# of them. Guarded on absence: edit or delete the active copy and it stays that
# way; the real opt-out is `triage: enabled: false` in the rendered config.yml,
# which this never touches.
CRON_SRC="${SCRIPT_DIR}/decree/cron.example/triage.md"
CRON_DST="${SCRIPT_DIR}/decree/cron/triage.md"
if [[ -f "${CRON_SRC}" && ! -e "${CRON_DST}" ]]; then
    mkdir -p "$(dirname "${CRON_DST}")"
    cp "${CRON_SRC}" "${CRON_DST}"
    echo "[decree] triage cron activated."
fi
