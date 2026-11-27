#!/usr/bin/env bash
# automation-backup — pre-startup init: the project's runtime dirs and its
# plugins. Off by default: backups are not Core. Nothing is scheduled until a plugin
# is on (./existential.sh plugin on triage, volume_backup, db_backup, ...); pruning
# finished runs is the one every project has.
#
# Runs on the host every `./existential.sh` while enabled; idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SCRIPT_DIR}/../.."

# A missing bind-mount source is created root-owned by Docker.
mkdir -p "${SCRIPT_DIR}"/{inbox,runs,store,lib,machines,plugins} "${REPO}/automation/secrets"

# Its machines are plugins (automation/plugins/, x-exist-project: backup), installed
# at this checkout's version every run, in adhoc where yq and decree are.
if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="$REPO" bash "${REPO}/src/plugins.sh" sync backup ||
        echo "[automation-backup] ⚠ the plugin sync failed (above); ./existential.sh plugin sync backup tries again."
else
    # A subshell: with no container runtime adhoc.sh exits, and this must not.
    # shellcheck source=../../src/utils/adhoc.sh
    ( . "${REPO}/src/utils/adhoc.sh"; run_adhoc env REPO_DIR=/repo bash /src/plugins.sh sync backup ) ||
        echo "[automation-backup] ⚠ the plugin sync failed (above); ./existential.sh plugin sync backup tries again."
fi
