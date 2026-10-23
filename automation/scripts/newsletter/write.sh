#!/usr/bin/env bash
# newsletter's write: the chat model (EXIST_MODEL_CHAT, on its own endpoint) reads
# $DECREE_LIB/newsletter/taste.md and the run's items.jsonl, and picks and summarises
# the items worth reading. Writes $DECREE_RUN_DIR/issue.md: a title with the date,
# then the model's picks as markdown links. With no new items it says so, without
# calling the model.
set -euo pipefail
# shellcheck source=../../lib/model.sh
source "${DECREE_LIB}/model.sh"
items="${DECREE_RUN_DIR}/items.jsonl"
taste="${DECREE_LIB}/newsletter/taste.md"
issue="${DECREE_RUN_DIR}/issue.md"
today="$(date +%F)"
: "${EXIST_MODEL_CHAT:?EXIST_MODEL_CHAT not set}"
export MODEL_TIMEOUT=600

if [ ! -s "${items}" ]; then
  printf '# Newsletter, %s\n\nNothing new in your feeds since the last issue.\n' "${today}" > "${issue}"
  echo "write: no new items; wrote the nothing-new issue without calling the model"
  exit 0
fi

instructions="You write a personal newsletter. The reader describes their taste below. Pick the items that fit it, and follow the format it asks for. Reply with the markdown list only: one line per item, '- [title](link): what it is and why it matters'. Use only links from the items given.

$(cat "${taste}")"

echo "write: asking ${EXIST_MODEL_CHAT} at $(model_url chat) about $(wc -l < "${items}") items"
picks="$(model_chat "${instructions}" "The new items, one JSON object per line:

$(cat "${items}")" 4000)"
if [ -z "${picks//[[:space:]]/}" ]; then
  echo "write: the model's reply has no content" >&2
  exit 1
fi

printf '# Newsletter, %s\n\n%s\n' "${today}" "${picks}" > "${issue}.tmp"
mv "${issue}.tmp" "${issue}"
echo "write: wrote issue.md"
