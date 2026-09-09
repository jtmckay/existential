#!/usr/bin/env bash
# decree — pre-startup init: activate the triage cron.
#
# Runs on the host (and in adhoc — it is a plain file copy inside the repo).
# Called every `./existential.sh` for an enabled decree; skips silently once the
# active copy exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# triage is `enabled: true` in config.exist.yml and deliberately not opt-in — a
# stack nobody is watching is exactly the one that needs it. But automation/cron/
# is gitignored (it is the user's active set), so the tracked template in
# automation-examples/cron/ is the only copy in git and the routine never ticks
# until something puts it in place. No quest owns this: 18 quests can enable
# decree, and triage has to work from all of them. Guarded on absence: edit or
# delete the active copy and it stays that way; the real opt-out is `triage:
# enabled: false` in the rendered config.yml, which this never touches.
CRON_SRC="${SCRIPT_DIR}/../../automation-examples/cron/triage.md"
CRON_DST="${SCRIPT_DIR}/../../automation/cron/triage.md"
if [[ -f "${CRON_SRC}" && ! -e "${CRON_DST}" ]]; then
    mkdir -p "$(dirname "${CRON_DST}")"
    cp "${CRON_SRC}" "${CRON_DST}"
    echo "[decree] triage cron activated."
fi

# workspace/README.md — the orientation doc. An agent confined to workspace/
# (hermes, OpenCode) has no other way to discover that ai/ and outbox/ are
# special: a bare directory listing shows three folders with nothing to tell
# it to go read either README. This is what a first listing should surface.
WORKSPACE_DIR="${SCRIPT_DIR}/../../workspace"
WORKSPACE_README="${WORKSPACE_DIR}/README.md"
if [[ ! -e "${WORKSPACE_README}" ]]; then
    mkdir -p "${WORKSPACE_DIR}"
    cat > "${WORKSPACE_README}" << 'WORKSPACEEOF'
# workspace/

Shared with every agent (Hermes at `/opt/data/workspace`, code-server at
`/workspace`) and indexed into OpenViking, so anything here is searchable and
citable. Two subdirectories mean something specific; everything else is
ordinary content — notes, plans, reference material, whatever you want an
agent to know about.

- **`outbox/`** — drop a markdown file here to run a decree routine. See
  `outbox/README.md` for the message format and `ai/decree-routines.md` for
  what's currently enabled and its parameters. This is the only supported way
  to trigger automation from inside workspace/ — there is no mount into
  `automation/` from here, and there deliberately never will be.
- **`ai/`** — automation output, not yours to write to. See `ai/README.md`.

This file is gitignored and nothing regenerates it — delete it once you have
your bearings.
WORKSPACEEOF
    echo "[decree] workspace/README.md created."
fi

# workspace/outbox/ — the one door from workspace/ into decree's inbox. An
# agent confined to workspace/ (hermes, OpenCode) has no mount into
# automation/ and must never be given one, so this README is how it learns
# where messages actually go. Relayed by lib/file-processors/outbox-relay.sh
# once EXIST_IS_NAS_SEAWEEDFS is enabled (Core quest activates it); until then the
# directory just sits there, harmlessly.
OUTBOX_README="${WORKSPACE_DIR}/outbox/README.md"
if [[ ! -e "${OUTBOX_README}" ]]; then
    mkdir -p "${WORKSPACE_DIR}/outbox"
    cat > "${OUTBOX_README}" << 'OUTBOXEOF'
# workspace/outbox/ — trigger decree from here

Drop a markdown file here to run a decree routine. Never write to `automation/`
directly — you (an agent reading this from inside workspace/) have no mount
into it, and that is deliberate: routine scripts are read-only from inside the
decree daemon on purpose, so the only supported way in is this directory.

```markdown
---
routine: agent-task
prompt: Summarize this week's notes.
correlation_id: D0002-1939-triage-0
---
```

`routine` is required — see `workspace/ai/decree-routines.md` (refreshed by the
`routines-snapshot` routine) for the current list, its description, and its
parameters. Any other frontmatter field becomes a parameter for that routine.

`correlation_id` is optional. If this task was itself triggered by a decree
workflow, that workflow's identifier is in your environment — include it here
so whatever eventually reads this message can trace it back to what started
the flow. It's a plain tag, not something decree groups by on its own: this
message still gets its own fresh chain either way. Leave it out for a
standalone request.

Setting it also makes the flow findable in Grafana — decree's own logging
picks up `correlation_id` from any message that sets it and puts it in the
Loki log line, so `{job="decree"} |= "correlation_id=<value>"` shows every
step of one flow across however many separate chains it actually ran as.

A file dropped here is picked up within about a second (via the object-store webhook,
not a poll) and relayed into decree's real inbox. This file is gitignored and
nothing regenerates it — delete it once you have your bearings.
OUTBOXEOF
    echo "[decree] workspace/outbox/ instructions created."
fi
