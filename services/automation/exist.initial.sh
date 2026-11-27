#!/usr/bin/env bash
# automation — pre-startup init: the project's runtime dirs and its plugins.
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
         "${PROJECT}"/{inbox,runs,store,machines,plugins,lib}
# decree reads .decree/.env; it is bind-mounted from automation/.env so config
# never lands in the synced workspace. A file mount needs its source to exist.
touch "${REPO}/automation/.env" "${PROJECT}/.env"

# ── workspace/.decree ────────────────────────────────────────────────────────
#
# The `automation` project is workspace/.decree. The repo's plugins are
# installed here, on the host, from automation/plugins/, at this checkout's
# version every run; a plugin of yours is a file in its .decree/plugins/, which
# `decree install <name>` installs from the workspace. `decree install` draws the graphs.
#
# Yours from their examples, once: what the webhook answers and which file
# changes start a run. An edit stays.
[[ -e "${PROJECT}/.gitignore" ]] || cp -p "${REPO}/automation/.gitignore" "${PROJECT}/.gitignore"
for _f in decree-go-rest handlers; do
    [[ -e "${PROJECT}/${_f}.yml" ]] || cp -p "${REPO}/automation/${_f}.exist.yml" "${PROJECT}/${_f}.yml"
done
# The plugin system, then the plugins this project has on (src/plugins.sh), each
# at the version in this checkout: its .decree/plugins/.on (the defaults, the first
# time) and all they need, their cron and order files included.
# In adhoc, where yq and decree are; a failure is said and the stack still comes up.
if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="$REPO" bash "${REPO}/src/plugins.sh" sync automation ||
        echo "[automation] ⚠ the plugin sync failed (above); ./existential.sh plugin sync tries again."
else
    # A subshell: with no container runtime adhoc.sh exits, and this must not.
    # shellcheck source=../../src/utils/adhoc.sh
    ( . "${REPO}/src/utils/adhoc.sh"; run_adhoc env REPO_DIR=/repo bash /src/plugins.sh sync automation ) ||
        echo "[automation] ⚠ the plugin sync failed (above); ./existential.sh plugin sync tries again."
fi

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
  daemon runs. `machines/<name>/graph.md` draws each machine, and
  `store/<name>/` holds what it keeps (yours to edit: feeds, departments).
  A new automation is one file in `.decree/plugins/<name>.md`, installed with
  `decree install <name>` from a terminal here.
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

Claude writes it as one file in `.decree/plugins/` and installs it with
`decree install <name>`. From then on it runs on its own, and `.decree/machines/<name>/graph.md` draws what it does.

A change to a matching file can start an automation too ("when a PDF lands in
`inbox/`, file it"); a folder listed in a `.gitignore` never starts one.

To hear back when it runs, install ntfy on your phone and subscribe to your
stack's topic.

Edit this note or delete it; nothing writes it again.
NOTEEOF
    echo "[decree] workspace/notes/my-first-note.md created."
fi
