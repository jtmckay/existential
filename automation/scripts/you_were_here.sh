#!/usr/bin/env bash
# You were here
#
# The morning digest: what needs you, what is holding steady, where you left off.
# lib/you-were-here/digest.ts gathers every section from files and renders the
# notes; the chat model, through lib/model.sh, writes only The picture, One next
# thing and the feed reasons from those gathered facts, and names one subject for
# Worth learning, whose article Wikipedia's search finds. With the model
# unreachable the digest is written and sent without them.
#
# Writes workspace/ai/you-were-here.md and ai/you-were-here/<YYYY>/<date>.md,
# and pushes through notify only when something changed since the last digest.
# automation-webhook's POST /you-were-here runs it on demand.
set -euo pipefail
# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"
digest="${DECREE_LIB}/you-were-here/digest.ts"

# A retry reuses the run dir: nothing from an earlier attempt may be read as this one.
rm -f "${DECREE_RUN_DIR}/model.json" "${DECREE_RUN_DIR}/learn.json" "${DECREE_RUN_DIR}/ntfy.md"
tsx "$digest" gather

system="You write the top of a person's morning digest from the facts given, and nothing else.
Reply with one JSON object and no other text:
{\"picture\": \"two or three sentences: where things stand\",
 \"next\": \"the one next thing to do, one sentence\",
 \"reasons\": {\"<feed item link>\": \"one line: why it relates to what they were working on\"},
 \"learn\": \"one subject they have been looking into lately, worth reading about properly, as a 2-5 word encyclopedia search phrase; empty if nothing stands out\"}
Use only the facts given. Link every claim to its source as a markdown link, [words](path),
using the path in parentheses after that fact. Calm and plain: no streaks, no counts of
missed days, no guilt, no praise. Leave reasons empty when there are no feed items."

if reply="$(MODEL_TIMEOUT=300 model_chat "$system" "$(cat "${DECREE_RUN_DIR}/prompt.txt")" 1500)" &&
    printf '%s' "$reply" | sed '/^```/d' |
        jq -ce 'select(type == "object") | {picture: (.picture // "" | tostring), next: (.next // "" | tostring),
                reasons: (.reasons // {} | if type == "object" then map_values(tostring) else {} end),
                learn: (.learn // "" | tostring)}' \
        > "${DECREE_RUN_DIR}/model.json" 2>/dev/null; then
    echo "you_were_here: the model wrote the picture and the next thing"
else
    rm -f "${DECREE_RUN_DIR}/model.json"
    echo "you_were_here: no usable answer from the model at $(model_url chat); writing the digest without it"
fi

tsx "$digest" learn || true
tsx "$digest" write

if [[ -f "${DECREE_RUN_DIR}/ntfy.md" ]]; then
    decree emit --machine notify --param ntfy_topic="$DECREE_DATA_NTFY_TOPIC" \
        --param ntfy_title="You were here" --param ntfy_tags=compass <"${DECREE_RUN_DIR}/ntfy.md" >/dev/null
    echo "you_were_here: pushed"
fi
