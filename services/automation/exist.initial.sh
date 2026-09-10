#!/usr/bin/env bash
# automation — pre-startup init: activate the triage cron (and migrate it off the
# `automation` daemon for installs that predate the move).
#
# Runs on the host (and in adhoc — it is a plain file copy inside the repo).
# Called every `./existential.sh` for an enabled decree; skips silently once the
# active copy exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# triage is `enabled: true` in the backup daemon's config.exist.yml and
# deliberately not opt-in — a stack nobody is watching is exactly the one that
# needs it. But cron/ is gitignored (it is the user's active set), so the tracked
# template is the only copy in git and the routine never ticks until something
# puts it in place. No quest owns this: 18 quests can enable automation, and
# triage has to work from all of them. Guarded on absence: edit or delete the
# active copy and it stays that way.
#
# triage runs in automation-backup, not automation — it needs the read-only
# /repo mount, and that mount is deliberately kept out of the container that
# runs an AI CLI. See .claude/reference/services.md.
CRON_SRC="${SCRIPT_DIR}/backup/cron.example/triage.md"
CRON_DST="${SCRIPT_DIR}/backup/cron/triage.md"
CRON_OLD="${SCRIPT_DIR}/../../automation/cron/triage.md"

# ── Migration: triage used to run in the `automation` daemon ─────────────────
#
# An install created before the move has the cron in automation/cron/ and the
# whitelists the wrong way round in the two RENDERED config.yml files, which are
# written once and never re-rendered — so nothing else will ever fix them. Left
# alone, triage would fire in a daemon that no longer has /repo (pre-check fails)
# while the daemon that does have it declines the routine as unlisted.
#
# Scoped to the exact pre-move fingerprint: only act when decree still says
# `true` AND backup still says `false`. A user who has deliberately turned triage
# off since is left alone, and re-running this is a no-op.
_triage_enabled_in() {   # <rendered config.yml> -> echoes true|false|missing
    local f="$1"
    [[ -f "$f" ]] || { echo missing; return; }
    awk '/^  triage:/ {found=1; next} found && /^    enabled:/ {print $2; exit}' "$f" \
        | grep -qE '^true$' && echo true || echo false
}
_set_triage_in() {       # <rendered config.yml> <true|false>
    local f="$1" want="$2"
    [[ -f "$f" ]] || return 0
    awk -v want="$want" '
        /^  triage:/ { print; intriage=1; next }
        intriage && /^    enabled:/ { print "    enabled: " want; intriage=0; next }
        { print }
    ' "$f" > "${f}.tmp" && cat "${f}.tmp" > "$f" && rm -f "${f}.tmp"
}

_DECREE_CFG="${SCRIPT_DIR}/decree/config.yml"
_BACKUP_CFG="${SCRIPT_DIR}/backup/config.yml"
if [[ "$(_triage_enabled_in "$_DECREE_CFG")" == "true" \
   && "$(_triage_enabled_in "$_BACKUP_CFG")" == "false" ]]; then
    _set_triage_in "$_DECREE_CFG" false
    _set_triage_in "$_BACKUP_CFG" true
    echo "[automation] triage moved to the automation-backup daemon (rendered configs updated)."
    if [[ -e "$CRON_OLD" && ! -e "$CRON_DST" ]]; then
        mkdir -p "$(dirname "$CRON_DST")"
        mv "$CRON_OLD" "$CRON_DST"
        echo "[automation] triage cron moved to services/automation/backup/cron/."
    else
        rm -f "$CRON_OLD"
    fi
    echo "[automation] restart both daemons to pick this up: docker compose up -d"
fi

# ── Migration: clean-runs used to sweep once a day ───────────────────────────
#
# `keep: 10` is a bound on what is on disk, and a daily sweep only made it true
# for one instant a day. workspace-sync fires every 10 minutes and triage every
# 5, so the shared runs/ dir reached 53 workspace-sync and 96 triage directories
# between passes. The routine itself was working — its last daily pass removed
# 405 — it just ran 1/144th as often as the things it cleans up after.
#
# The tracked template now says */15. An active cron/ copy is gitignored and
# never re-rendered, so without this an existing install keeps the daily
# schedule forever. Scoped to the exact old value, so a deliberately customised
# schedule is left alone, and idempotent once bumped.
_CLEAN_CRON="${SCRIPT_DIR}/../../automation/cron/clean-runs.md"
if [[ -f "$_CLEAN_CRON" ]] && grep -qF 'cron: "0 10 * * *"' "$_CLEAN_CRON"; then
    _tmp="$(mktemp)"
    sed 's|^cron: "0 10 \* \* \*"$|cron: "*/15 * * * *"|' "$_CLEAN_CRON" > "$_tmp"
    cat "$_tmp" > "$_CLEAN_CRON"   # preserve inode: cron/ is a live bind mount
    rm -f "$_tmp"
    echo "[automation] clean-runs schedule bumped daily -> */15 (restart automation to apply)."
fi

if [[ -f "${CRON_SRC}" && ! -e "${CRON_DST}" ]]; then
    mkdir -p "$(dirname "${CRON_DST}")"
    cp "${CRON_SRC}" "${CRON_DST}"
    echo "[automation] triage cron activated."
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
