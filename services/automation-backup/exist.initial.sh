#!/usr/bin/env bash
# automation-backup — pre-startup init: the project's runtime dirs and the crons
# it always runs. Off by default: backups are not Core.
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
mkdir -p "${SCRIPT_DIR}"/{inbox,runs,store,cron,lib,scripts} "${REPO}/automation/secrets"

# triage watches the stack, and clean-runs keeps this daemon's runs/ from
# growing; workspace-sync does nothing until its Nextcloud keys are set. cron/
# is the user's active set, so each is copied once: edit or delete a copy and it
# stays that way.
for _cron in triage.md clean-runs.md workspace-sync.md; do
    if [[ ! -e "${SCRIPT_DIR}/cron/${_cron}" ]]; then
        cp "${SCRIPT_DIR}/cron.example/${_cron}" "${SCRIPT_DIR}/cron/${_cron}"
        echo "[automation-backup] ${_cron%.md} cron activated."
    fi
done
