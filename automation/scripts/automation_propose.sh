#!/usr/bin/env bash
# automation_propose — one standing instruction, written as the migration that
# would build it.
#
# note_watch found it. The chat model writes the migration's body: why (the
# person's own words), the outcome (what triggers it, what it does, where the
# results go), constraints and acceptance criteria, all declarative: what is
# true when it exists, never how to build it. This writes it to
# ai/proposed/<name>.md and tells you. Nothing is built: moving the
# file into notes/automations/ is how you accept it, and then `develop` builds
# the machine and its trigger from it (reconcile hands it over).
set -euo pipefail
# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"
# shellcheck source=../lib/firecrawl.sh
source "${DECREE_LIB}/firecrawl.sh"

WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
name="$DECREE_DATA_NAME" when="$DECREE_DATA_WHEN" steps="$DECREE_DATA_STEPS" rel="$DECREE_DATA_NOTE_PATH"
[[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "automation_propose: '${name}' is not a machine name" >&2; exit 1; }
# Never a name already taken: building it would replace that machine.
base="$name"; n=2
while [[ -e ".decree/machines/${name}.yml" || -e "${WS}/notes/automations/${name}.md" || -e "${WS}/ai/proposed/${name}.md" ]]; do
    name="${base}_${n}"; n=$((n + 1))
done

system='You write a decree migration: the declarative spec of one automation, which
another step will build. Describe what is true once it exists, never how to build it.
Reply with only Markdown, no fences, in exactly this shape:
# <the automation, as one outcome sentence>
## Overview
Why it is wanted, quoting the person'"'"'s instruction.
## Outcome
- What starts it: a note of theirs that is <the event>, or a file matching <a glob> changing,
  or a schedule (<when, in words>). Choose the one their instruction means.
- What it produces, one bullet per step, as results (what is found or written).
- When they ask for a judgement (is it worth building, buying, doing), the first result is
  the verdict: favorable, unfavorable, or already done by someone, named.
- Its results are written to ai/automations/<name>/ and their first lines sent to their phone.
- Anything that needs the person (pay, sign up, send, decide) is listed for them, not done.
## Constraints
- It reads only what triggered it and public, read-only web sources, and the language model.
- It writes nothing outside ai/automations/<name>/ and sends nothing but that notification.
## Acceptance Criteria
- **Given** <the trigger> **When** <it happens> **Then** <an observable result>
(two or three of these)'
if firecrawl_on; then system+='
The stack can search and read the web, so research steps search it and cite their sources.'
else system+='
The stack cannot search the web: a step that needs it is listed for the person instead.'
fi
user="Name: ${name}
When: ${when}
Steps the person asked for:
${steps}
Asked for in: ${rel}"

body="$(MODEL_TIMEOUT=300 model_chat "$system" "$user" 2000 | sed '/^```/d')" || { echo "automation_propose: no answer from the model" >&2; exit 1; }
for section in "## Overview" "## Outcome" "## Constraints" "## Acceptance Criteria"; do
    grep -qxF "$section" <<<"$body" || { echo "automation_propose: the migration has no '${section}' section" >&2; exit 1; }
done

out="${WS}/ai/proposed/${name}.md"
mkdir -p "$(dirname "$out")"
{
    printf -- '---\nmachine: develop\nautomation: %s\nfrom: %s\n---\n\n' "$name" "$rel"
    printf '%s\n' "$body"
} > "${out}.tmp"
mv "${out}.tmp" "$out"
echo "automation_propose: wrote ${out#"${WS}/"}"

printf 'When %s, I can %s\n\nTo build it, move ai/proposed/%s.md into notes/automations/. Read or edit what it will do first.\n' \
    "$when" "$(printf '%s\n' "$steps" | sed 's/^- //' | paste -sd ';' | sed 's/;/; /g')" "$name" |
    decree emit --machine notify --param ntfy_title="An automation you could have" --param ntfy_tags=bulb >/dev/null
