#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN/CRITERIA/IS_PRE_SIGNED are read out of this
# file's source by file-router and file-processor, not by sourcing it.
# Agent handoff — the end-to-end example: match a file, judge it, hand it to an agent.
#
# This is the shape most matches want. The two tests do different jobs:
#
#   PATTERN  narrows to markdown anywhere in the synced workspace. Free.
#   CRITERIA decides whether this particular note is worth a full agent run.
#            One model call, and it answers NO unless it genuinely matches.
#
# What survives both gets handed to agent-task, which calls the hermes gateway
# — so it can search OpenViking and the web without anything here saying
# how. The answer lands in workspace/ai/, which is indexed but never synced, so
# it is searchable next time and cannot trigger another run.
#
# Rewrite CRITERIA. It is the whole judgment, and looking for the wrong thing is
# the only way this setup wastes real work.
#
# Copy to lib/file-processors/ to activate — no restart needed; file-router
# reads the directory per event.
PATTERN="^nextcloud:workspace/.*\.md$"
CRITERIA="an open question or decision the author has not resolved — something where going and finding out would actually help them"
IS_PRE_SIGNED=false

# Env vars available when this script runs:
#   FILE_SOURCE        full rclone source path   e.g. "nextcloud:workspace/notes/plan.md"
#   FILE_KEY           path after "remote:"      e.g. "workspace/notes/plan.md"
#   FILE_ACTION        "created" or "removed"
#   FILE_PATH          absolute local temp path
#   FILE_MATCH_REASON  the model's one-line reason this file matched
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to hand off."
    exit 0
fi

# Path relative to the workspace root: FILE_KEY is "workspace/<path>", the
# Nextcloud folder the workspace_data volume is mounted at.
_rel="${FILE_KEY#workspace/}"
_slug="$(basename "$_rel" .md)"

echo "Handing off: ${_rel}"
echo "Because:     ${FILE_MATCH_REASON:-(no reason recorded)}"

# agent_task answers on the default hermes profile. Add `--param profile=research`
# to use a department's toolset instead, or emit hermes_router to let the router
# pick the department. See site/docs/decree/routing.md. Either has to be in
# file_processor's `emits:` (automation/machines/file_processor.yml).
decree emit --machine agent_task \
    --param file_path="$_rel" \
    --param output_name="${_slug}-followup" \
    --param prompt="This note was flagged: ${FILE_MATCH_REASON:-it contains an unresolved question}. Read it, work out what can be settled without the author, and list the few questions only they can answer." \
    < "$FILE_PATH" >/dev/null

echo "Queued agent_task for ${_rel}."
