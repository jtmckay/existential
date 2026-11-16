#!/usr/bin/env bash
# automation-backup — pre-startup init: the project's runtime dirs and its
# plugins. Off by default: backups are not Core. Nothing is scheduled until a flow
# is on (./existential.sh flow on service-triage, backup-<service>, ...); clean-runs
# is the one every install starts with.
#
# Runs on the host every `./existential.sh` while enabled; idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SCRIPT_DIR}/../.."

# An install from before this was its own folder kept the project in
# services/automation/backup/. Each piece of runtime state moves over once.
_old="${REPO}/services/automation/backup"
for _f in cron inbox runs store processed.md; do
    if [[ -e "${_old}/${_f}" && ! -e "${SCRIPT_DIR}/${_f}" ]]; then
        mv "${_old}/${_f}" "${SCRIPT_DIR}/${_f}"
        echo "[automation-backup] services/automation/backup/${_f} moved here."
    fi
done

# A missing bind-mount source is created root-owned by Docker.
mkdir -p "${SCRIPT_DIR}"/{inbox,runs,store,cron,lib,machines,scripts} "${REPO}/automation/secrets"

# Its machines are plugins (automation/plugins/, project: backup), installed
# at this checkout's version every run, in adhoc where yq and decree are.
if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="$REPO" bash "${REPO}/src/lib/plugin.sh" sync backup ||
        echo "[automation-backup] ⚠ the plugin sync failed (above); ./existential.sh run plugin sync backup tries again."
else
    # A subshell: with no container runtime adhoc.sh exits, and this must not.
    # shellcheck source=../../src/utils/adhoc.sh
    ( . "${REPO}/src/utils/adhoc.sh"; run_adhoc env REPO_DIR=/repo bash /src/lib/plugin.sh sync backup ) ||
        echo "[automation-backup] ⚠ the plugin sync failed (above); ./existential.sh run plugin sync backup tries again."
fi
