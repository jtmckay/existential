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
WORKSPACE_DIR="${REPO}/volumes/workspace_data"
PROJECT="${WORKSPACE_DIR}/.decree"
mkdir -p "${REPO}"/automation/secrets \
         "${PROJECT}"/{inbox,runs,store,cron,migrations,lib,graph} \
         "${SCRIPT_DIR}"/backup/{inbox,runs,store,cron,lib,scripts}
# decree reads .decree/.env; it is bind-mounted from automation/.env so config
# never lands in the synced workspace. A file mount needs its source to exist.
touch "${REPO}/automation/.env" "${PROJECT}/.env"

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
_upgrade_dir() {         # <active dir> <template glob, NAME for the file> [processed.md]
    local active="$1" templates="$2" processed="${3:-}" f name t
    for f in "$active"/*.md; do
        [[ -f "$f" ]] && grep -q '^routine:' "$f" || continue
        name="${f##*/}"
        [[ -n "$processed" && -f "$processed" ]] && grep -qxF "$name" "$processed" && continue
        mkdir -p "${_archive}/${active#"${REPO}/"}"
        cp -p "$f" "${_archive}/${active#"${REPO}/"}/"
        t="$(compgen -G "${templates//NAME/${name}}" | head -1 || true)"
        if [[ -n "$t" ]]; then
            cat "$t" > "$f"   # preserve inode: a live bind mount
            echo "[automation] ${active#"${REPO}/"}/${name}: replaced by its decree 0.5 template."
        else
            rm -f "$f"
            echo "[automation] ${active#"${REPO}/"}/${name}: removed — nothing in decree 0.5 runs it."
        fi
    done
}
_upgrade_dir "${REPO}/automation/cron" "${REPO}/flows/*/cron/NAME"
_upgrade_dir "${REPO}/automation/migrations" "${REPO}/flows/*/migrations/NAME" "${REPO}/automation/processed.md"
_upgrade_dir "${SCRIPT_DIR}/backup/cron" "${SCRIPT_DIR}/backup/cron.example/NAME"
[[ -d "$_archive" ]] && echo "[automation] the 0.4 copies are in ${_archive#"${REPO}/"}/ — re-apply any schedule you had customised."
# The 0.4 daemon configs and their hash files: nothing reads them any more.
rm -f "${SCRIPT_DIR}/decree/config.yml" "${SCRIPT_DIR}/backup/config.yml" \
      "${SCRIPT_DIR}/backup/config.hash" "${REPO}/automation/config.hash" \
      "${SCRIPT_DIR}/webhook/config.yml" "${REPO}/automation/config.yml" \
      "${REPO}/automation/precheck.log" "${SCRIPT_DIR}/backup/precheck.log"
rmdir "${SCRIPT_DIR}/backup/shared_routines" \
      "${REPO}/automation/outbox" "${SCRIPT_DIR}/backup/outbox" 2>/dev/null || true

# ── workspace/.decree ────────────────────────────────────────────────────────
#
# The `automation` project is workspace/.decree, where the user (and the agents
# they direct) write automations. The repo's machines and scripts are its
# starting set: each file is copied once and never again, so an edit wins, the
# same contract as a rendered file. lib/ is not copied: it is the repo's,
# mounted read-only over lib/ so it stays current with the checkout.
_seed() {               # <src> <dst>: copy every file under src that dst lacks
    local f
    while IFS= read -r f; do
        [[ -e "$2/$f" ]] && continue
        mkdir -p "$(dirname "$2/$f")"
        cp -p "$1/$f" "$2/$f"
    done < <(cd "$1" && find . -type f ! -name '.gitkeep' | sed 's|^\./||')
}
_seed "${REPO}/automation/machines" "${PROJECT}/machines"
_seed "${REPO}/automation/scripts" "${PROJECT}/scripts"
# The committed graphs, so the workspace draws every machine from the first
# render; the daemon redraws them from what is actually there once it is up.
_seed "${REPO}/automation/graph" "${PROJECT}/graph"
for _f in .gitignore decree-go-rest.yml handlers.yml; do
    [[ -e "${PROJECT}/${_f}" ]] || cp -p "${REPO}/automation/${_f}" "${PROJECT}/${_f}"
done
# An install from before this keeps its active crons and migrations, and its
# record of which migrations ran, in automation/. Each moves over once, unless
# the workspace already has that file.
for _f in "${REPO}"/automation/{cron,migrations}/*.md "${REPO}/automation/processed.md"; do
    _dst="${PROJECT}/${_f#"${REPO}/automation/"}"
    if [[ -f "$_f" && ! -e "$_dst" ]]; then
        mv "$_f" "$_dst"
        echo "[automation] ${_f#"${REPO}/"} moved to workspace/.decree/."
    fi
done

# triage is deliberately not opt-in — a stack nobody is watching is exactly the
# one that needs it — and clean-runs comes with it, because triage fires every
# few minutes and this daemon's runs/ is its own. But cron/ is gitignored (it is
# the user's active set), so the tracked templates are the only copies in git
# and nothing ticks until something puts them in place. Every install with
# automation needs it, whichever flows are on. Guarded
# on absence: edit or delete an active copy and it stays that way.
#
# triage runs in automation-backup, not automation — it needs the read-only
# /repo mount, and that mount is deliberately kept out of the container that
# hands prompts to hermes. See .claude/reference/services.md.
#
# workspace-sync rides along: it does nothing until its Nextcloud keys are set,
# so turning it on is filling in .env, not finding a cron file.
for _cron in triage.md clean-runs.md workspace-sync.md; do
    if [[ ! -e "${SCRIPT_DIR}/backup/cron/${_cron}" ]]; then
        cp "${SCRIPT_DIR}/backup/cron.example/${_cron}" "${SCRIPT_DIR}/backup/cron/${_cron}"
        echo "[automation] ${_cron%.md} cron activated (automation-backup)."
    fi
done

# The default flows (`default: true` in flows/<name>/flow.md: the digest, the
# look backs, clean-runs, health-checks) are on until `./existential.sh flow off`
# names one in .decree/flows-off. Each missing file is copied in; an edited copy
# stays as you left it.
REPO_DIR="$REPO"   # read by src/utils/flows.sh
export REPO_DIR
# shellcheck source=../../src/utils/flows.sh
. "${REPO}/src/utils/flows.sh"
for _flow in $(flow_defaults); do
    while IFS= read -r _f; do
        [[ -n "$_f" ]] && echo "[automation] ${_flow}: ${_f#"${FLOWS_DECREE}/"} activated."
    done < <(flow_activate "$_flow")
done

# workspace/README.md — the orientation doc. An agent confined to workspace/
# (hermes) has no other way to discover that ai/ is special: a bare directory
# listing shows folders with nothing to tell it to go read the README. This is
# what a first listing should surface.
WORKSPACE_README="${WORKSPACE_DIR}/README.md"
if [[ ! -e "${WORKSPACE_README}" ]]; then
    mkdir -p "${WORKSPACE_DIR}"
    cat > "${WORKSPACE_README}" << 'WORKSPACEEOF'
# workspace/

Your folder, shared with every agent the stack runs (code-server at
`/workspace`, Hermes at `/opt/data/workspace`). Everything here is ordinary
content — notes, plans, reference material — except:

- **`notes/`** — your notes, plain markdown. Start with `my-first-note.md`.
- **`.decree/`** — your automations: the decree project the `automation`
  daemon runs. `graph/` draws every machine and is redrawn when one changes.
- **`.claude/`** — the decree skill, so `claude` started here knows how to
  write a machine.
- **`ai/`** — automation output, not yours to write to. See `ai/README.md`,
  and `ai/decree/` for what decree can run and how to ask it to.

Nothing regenerates this file — delete it once you have your bearings.
WORKSPACEEOF
    echo "[decree] workspace/README.md created."
fi

# notes/my-first-note.md — the loop, in the user's terms. Written once; an edit
# or a delete stays that way.
FIRST_NOTE="${WORKSPACE_DIR}/notes/my-first-note.md"
if [[ ! -e "${FIRST_NOTE}" ]]; then
    mkdir -p "${WORKSPACE_DIR}/notes"
    cat > "${FIRST_NOTE}" << 'NOTEEOF'
# My first note

This folder is yours. Write here: ideas, lists, things you keep meaning to do.

When something should happen on its own — a reminder, a weekly look back,
tidying a folder — open a terminal here in code-server, start `claude`, and say
what should happen, in your own words.

Claude writes it as an automation in `.decree/`, the folder next to `notes/`.
It starts running on its own, and `.decree/graph/` draws what it does.

A change to a matching file can start an automation too ("when a PDF lands in
`inbox/`, file it"); a folder listed in a `.gitignore` never starts one.

To hear back when it runs, install ntfy on your phone and subscribe to your
stack's topic.

Edit this note or delete it; nothing writes it again.
NOTEEOF
    echo "[decree] workspace/notes/my-first-note.md created."
fi
