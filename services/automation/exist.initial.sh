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
         "${PROJECT}"/{inbox,runs,store,cron,migrations,lib,graph}
# decree reads .decree/.env; it is bind-mounted from automation/.env so config
# never lands in the synced workspace. A file mount needs its source to exist.
touch "${REPO}/automation/.env" "${PROJECT}/.env"

# ── decree 0.4 -> 0.5 ────────────────────────────────────────────────────────
#
# cron/ and migrations/ are the user's active copies: gitignored, copied once
# from a template and never re-rendered. A 0.4 copy names `routine:`, which 0.5
# rejects — the daemon refuses to start on one invalid pending migration, and a
# 0.4 cron file is a failed run every time it fires. So each one is archived and
# removed: the plugin that runs it writes the current one. Processed migrations
# are left alone: decree never reads them again.
_archive="${REPO}/archive/decree-0.4-$(date +%Y%m%d-%H%M%S)"
_upgrade_dir() {         # <active dir> [processed.md]
    local active="$1" processed="${2:-}" f name
    for f in "$active"/*.md; do
        [[ -f "$f" ]] && grep -q '^routine:' "$f" || continue
        name="${f##*/}"
        [[ -n "$processed" && -f "$processed" ]] && grep -qxF "$name" "$processed" && continue
        mkdir -p "${_archive}/${active#"${REPO}/"}"
        cp -p "$f" "${_archive}/${active#"${REPO}/"}/"
        rm -f "$f"
        echo "[automation] ${active#"${REPO}/"}/${name}: removed — the plugin that runs it writes the current one."
    done
}
_upgrade_dir "${REPO}/automation/cron"
_upgrade_dir "${REPO}/automation/migrations" "${REPO}/automation/processed.md"
[[ -d "$_archive" ]] && echo "[automation] the 0.4 copies are in ${_archive#"${REPO}/"}/ — re-apply any schedule you had customised."
# The 0.4 daemon configs and their hash files: nothing reads them any more.
rm -f "${SCRIPT_DIR}/decree/config.yml" "${REPO}/automation/config.hash" \
      "${SCRIPT_DIR}/webhook/config.yml" "${REPO}/automation/config.yml" \
      "${REPO}/automation/precheck.log"
rmdir "${REPO}/automation/outbox" 2>/dev/null || true

# ── workspace/.decree ────────────────────────────────────────────────────────
#
# The `automation` project is workspace/.decree, where the user (and the agents
# they direct) write automations. The plugin system and the plugins it has on
# come from the repo, kept at this checkout's version every run, with lib/: the
# shared automation/lib/ and each plugin's own lib files. The daemon draws the graphs.
# Yours from their examples, once: what the webhook answers and which file
# changes start a run. An edit stays.
[[ -e "${PROJECT}/.gitignore" ]] || cp -p "${REPO}/automation/.gitignore" "${PROJECT}/.gitignore"
for _f in decree-go-rest handlers; do
    [[ -e "${PROJECT}/${_f}.yml" ]] || cp -p "${REPO}/automation/${_f}.exist.yml" "${PROJECT}/${_f}.yml"
done
# The plugin system, then the plugins this install has on (src/lib/plugin.sh),
# each at the version in this checkout: what plugins.yml has on (the flows and
# machines; written from automation/plugins.exist.yml the first time) and all
# they need, their crons and migrations included.
# In adhoc, where yq and decree are; a failure is said and the stack still comes up.
if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="$REPO" bash "${REPO}/src/lib/plugin.sh" sync automation ||
        echo "[automation] ⚠ the plugin sync failed (above); ./existential.sh run plugin sync tries again."
else
    # A subshell: with no container runtime adhoc.sh exits, and this must not.
    # shellcheck source=../../src/utils/adhoc.sh
    ( . "${REPO}/src/utils/adhoc.sh"; run_adhoc env REPO_DIR=/repo bash /src/lib/plugin.sh sync automation ) ||
        echo "[automation] ⚠ the plugin sync failed (above); ./existential.sh run plugin sync tries again."
fi
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

# workspace/README.md — the orientation doc. An agent confined to workspace/
# (pi, in a department without bash) has no other way to discover that ai/ is special: a bare directory
# listing shows folders with nothing to tell it to go read the README. This is
# what a first listing should surface.
WORKSPACE_README="${WORKSPACE_DIR}/README.md"
if [[ ! -e "${WORKSPACE_README}" ]]; then
    mkdir -p "${WORKSPACE_DIR}"
    cat > "${WORKSPACE_README}" << 'WORKSPACEEOF'
# workspace/

Your folder, shared with every agent the stack runs (pi and Claude, in
code-server and in automation, all at `/workspace`). Everything here is ordinary
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
