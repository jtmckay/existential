#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN/CRITERIA/IS_PRE_SIGNED are read out of this
# file's source by minio-router and file-processor, not by sourcing it.
# Agent handoff — the end-to-end example: match a file, judge it, hand it to an agent.
#
# This is the shape most matches want. The two tests do different jobs:
#
#   PATTERN  narrows to markdown anywhere in the synced workspace. Free.
#   CRITERIA decides whether this particular note is worth a full agent run.
#            One model call, and it answers NO unless it genuinely matches.
#
# What survives both gets handed to agent-task, which runs OpenCode against
# hermes — so it can search OpenViking and the web without anything here saying
# how. The answer lands in workspace/ai/, which is indexed but never synced, so
# it is searchable next time and cannot trigger another run.
#
# Rewrite CRITERIA. It is the whole judgment, and looking for the wrong thing is
# the only way this setup wastes real work.
#
# Copy to lib/file-processors/ to activate — no restart needed; minio-router
# reads the directory per event.
PATTERN="minio:workspace/.*\.md$"
CRITERIA="an open question or decision the author has not resolved — something where going and finding out would actually help them"
IS_PRE_SIGNED=false

# Env vars available when this script runs:
#   FILE_SOURCE        full rclone source path   e.g. "minio:workspace/notes/plan.md"
#   FILE_KEY           path after "remote:"      e.g. "workspace/notes/plan.md"
#   FILE_ACTION        "created" or "removed"
#   FILE_PATH          absolute local temp path
#   FILE_MATCH_REASON  the model's one-line reason this file matched
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to hand off."
    exit 0
fi

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
# decree reads the outbox but never creates it — an absent dir is silently
# treated as "no messages", so a handoff would vanish without an error.
mkdir -p "$OUTBOX_DIR"

# Path relative to the workspace root: FILE_KEY is "workspace/<path>" because the
# bucket is named workspace. agent-task reports it as workspace/<path>.
_rel="${FILE_KEY#workspace/}"
_slug="$(basename "$_rel" .md)"

echo "Handing off: ${_rel}"
echo "Because:     ${FILE_MATCH_REASON:-(no reason recorded)}"

cat > "${OUTBOX_DIR}/agent-handoff-$(date +%s%N).md" << EOF
---
# agent-task answers on the default hermes profile. Add `profile: research` to
# use a department's toolset instead, or swap the routine for hermes-router to
# let the router pick the department. See site/docs/decree/routing.md.
routine: agent-task
file_path: $(jq -rn --arg v "$_rel" '$v|@json')
output_name: $(jq -rn --arg v "${_slug}-followup" '$v|@json')
prompt: $(jq -rn --arg v "This note was flagged: ${FILE_MATCH_REASON:-it contains an unresolved question}. Read it, work out what can be settled without the author, and list the few questions only they can answer." '$v|@json')
---

$(cat "$FILE_PATH")
EOF

echo "Queued agent-task for ${_rel}."
