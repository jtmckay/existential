#!/usr/bin/env bash
# automation — pre-startup init: the projects' runtime dirs, the triage cron, and
# the one-time move of an existing install's active files to decree 0.5.
#
# Runs on the host (and in adhoc — it is a plain file copy inside the repo).
# Called every `./existential.sh` for an enabled decree; idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SCRIPT_DIR}/../.."

# Every bind-mount source a container needs to write must exist, owned by us,
# before compose starts: a missing one is created root-owned by Docker, and
# automation-webhook queuing into a root-owned inbox/ is a daemon that can never
# claim a message.
mkdir -p "${REPO}"/automation/{inbox,runs,store,cron,migrations,secrets} \
         "${SCRIPT_DIR}"/backup/{inbox,runs,store,cron,lib,scripts}

# ── decree 0.4 -> 0.5 ────────────────────────────────────────────────────────
#
# cron/ and migrations/ are the user's active copies: gitignored, copied once
# from a template and never re-rendered. A 0.4 copy names `routine:`, which 0.5
# rejects — the daemon refuses to start on one invalid pending migration, and a
# 0.4 cron file is a failed run every time it fires. So each one is replaced by
# its current template, the old copy archived first. A file with no template any
# more (its routine is gone) is only archived. Processed migrations are left
# alone: decree never reads them again.
_archive="${REPO}/archive/decree-0.4-$(date +%Y%m%d-%H%M%S)"
_upgrade_dir() {         # <active dir> <template dir> [processed.md]
    local active="$1" templates="$2" processed="${3:-}" f name
    for f in "$active"/*.md; do
        [[ -f "$f" ]] && grep -q '^routine:' "$f" || continue
        name="${f##*/}"
        [[ -n "$processed" && -f "$processed" ]] && grep -qxF "$name" "$processed" && continue
        mkdir -p "${_archive}/${active#"${REPO}/"}"
        cp -p "$f" "${_archive}/${active#"${REPO}/"}/"
        if [[ -f "${templates}/${name}" ]]; then
            cat "${templates}/${name}" > "$f"   # preserve inode: a live bind mount
            echo "[automation] ${active#"${REPO}/"}/${name}: replaced by its decree 0.5 template."
        else
            rm -f "$f"
            echo "[automation] ${active#"${REPO}/"}/${name}: removed — nothing in decree 0.5 runs it."
        fi
    done
}
_upgrade_dir "${REPO}/automation/cron" "${REPO}/automation-examples/cron"
_upgrade_dir "${REPO}/automation/migrations" "${REPO}/automation-examples/migrations" "${REPO}/automation/processed.md"
_upgrade_dir "${SCRIPT_DIR}/backup/cron" "${SCRIPT_DIR}/backup/cron.example"
[[ -d "$_archive" ]] && echo "[automation] the 0.4 copies are in ${_archive#"${REPO}/"}/ — re-apply any schedule you had customised."
# The 0.4 daemon configs and their hash files: nothing reads them any more.
rm -f "${SCRIPT_DIR}/decree/config.yml" "${SCRIPT_DIR}/backup/config.yml" \
      "${SCRIPT_DIR}/backup/config.hash" "${REPO}/automation/config.hash" \
      "${SCRIPT_DIR}/webhook/config.yml" "${REPO}/automation/config.yml" \
      "${REPO}/automation/precheck.log" "${SCRIPT_DIR}/backup/precheck.log"
rmdir "${SCRIPT_DIR}/backup/shared_routines" \
      "${REPO}/automation/outbox" "${SCRIPT_DIR}/backup/outbox" 2>/dev/null || true

# triage is deliberately not opt-in — a stack nobody is watching is exactly the
# one that needs it — and clean-runs comes with it, because triage fires every
# few minutes and this daemon's runs/ is its own. But cron/ is gitignored (it is
# the user's active set), so the tracked templates are the only copies in git
# and nothing ticks until something puts them in place. No quest owns this: 18
# quests can enable automation, and triage has to work from all of them. Guarded
# on absence: edit or delete an active copy and it stays that way.
#
# triage runs in automation-backup, not automation — it needs the read-only
# /repo mount, and that mount is deliberately kept out of the container that
# hands prompts to hermes. See .claude/reference/services.md.
for _cron in triage.md clean-runs.md; do
    if [[ ! -e "${SCRIPT_DIR}/backup/cron/${_cron}" ]]; then
        cp "${SCRIPT_DIR}/backup/cron.example/${_cron}" "${SCRIPT_DIR}/backup/cron/${_cron}"
        echo "[automation] ${_cron%.md} cron activated (automation-backup)."
    fi
done

# workspace/README.md — the orientation doc. An agent confined to workspace/
# (hermes) has no other way to discover that ai/ is special: a bare directory
# listing shows folders with nothing to tell it to go read the README. This is
# what a first listing should surface.
WORKSPACE_DIR="${REPO}/volumes/workspace_data"
WORKSPACE_README="${WORKSPACE_DIR}/README.md"
if [[ ! -e "${WORKSPACE_README}" ]]; then
    mkdir -p "${WORKSPACE_DIR}"
    cat > "${WORKSPACE_README}" << 'WORKSPACEEOF'
# workspace/

Shared with every agent (Hermes at `/opt/data/workspace`, code-server at
`/workspace`), synced to your own machines through Nextcloud's `workspace`
folder, and indexed into OpenViking, so anything here is searchable and
citable. One subdirectory means something specific; everything else is
ordinary content — notes, plans, reference material, whatever you want an
agent to know about.

- **`ai/`** — automation output, not yours to write to. See `ai/README.md`,
  and `ai/decree/` for what decree can run and how to ask it to.

Nothing regenerates this file — delete it once you have your bearings.
WORKSPACEEOF
    echo "[decree] workspace/README.md created."
fi
