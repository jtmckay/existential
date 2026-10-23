#!/usr/bin/env bash
# Look back
#
# "What did I even do this year?": a range of the "you were here" archive, read
# into Highlights, Themes, Decisions made and By the numbers by
# lib/look-back/look-back.ts. The chat model, through lib/model.sh, writes only
# In short from those facts; with the model unreachable the look back is the data
# sections alone. Reads the archive, never rewrites it.
#
# Writes notes/you-were-here/<YYYY>/look-back-<from>-<to>.md (-work.md for the
# work scope) and pushes a short pointer to it through notify.
# automation-webhook's POST /look-back runs it on demand.
set -euo pipefail
# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"
look_back="${DECREE_LIB}/look-back/look-back.ts"

# A retry reuses the run dir: nothing from an earlier attempt may be read as this one.
rm -f "${DECREE_RUN_DIR}"/{facts.json,model.json,ntfy.md}
tsx "$look_back" gather
[[ -f "${DECREE_RUN_DIR}/facts.json" ]] || exit 0

system="You write the opening of a person's look back over a stretch of their days, from the facts given, and nothing else.
Reply with one JSON object and no other text:
{\"summary\": \"one short paragraph: what this stretch was about, grouped as you see fit\"}
Use only the facts given. Link every claim to the day note it came from as a markdown link,
[words](path), using the path in parentheses after that fact. Plain and calm: no judgement,
no praise, no counts of missed days."

if reply="$(MODEL_TIMEOUT=300 model_chat "$system" "$(cat "${DECREE_RUN_DIR}/prompt.txt")" 1000)" &&
    printf '%s' "$reply" | sed '/^```/d' |
        jq -ce 'select(type == "object") | {summary: (.summary // "" | tostring)}' \
        > "${DECREE_RUN_DIR}/model.json" 2>/dev/null; then
    echo "look_back: the model wrote In short"
else
    rm -f "${DECREE_RUN_DIR}/model.json"
    echo "look_back: no usable answer from the model at $(model_url chat); writing the data sections alone"
fi

tsx "$look_back" write

decree emit --machine notify --param ntfy_topic="$DECREE_DATA_NTFY_TOPIC" \
    --param ntfy_title="Look back" --param ntfy_tags=calendar <"${DECREE_RUN_DIR}/ntfy.md" >/dev/null
echo "look_back: pushed"
