#!/usr/bin/env bash
# automations/run.sh — the frame every accepted automation runs in.
#
# Sourced by .decree/scripts/<name>.sh, which the workspace's develop machine
# writes from an accepted automation's migration: this file, then the `steps`
# function the model wrote, then `automation_run <name>`. Everything but `steps`
# is here, the same for every automation.
#
# steps() gets the file that triggered it, if any, and prints its results as
# Markdown:
#   NOTE_PATH   the note or file, relative to the workspace; empty on a schedule
#   NOTE        its text; empty on a schedule
#   ask <instructions> <input>   one answer from the chat model
#   web_search <query> [n]       the top n web results with their pages' text,
#   web_read <url>               and one page, both through Firecrawl (firecrawl.sh)
# automation_run writes what steps printed to workspace/ai/automations/<name>/
# and sends its first lines to ntfy.
set -euo pipefail
# shellcheck source=../model.sh
source "${DECREE_LIB}/model.sh"
# shellcheck source=../firecrawl.sh
source "${DECREE_LIB}/firecrawl.sh"

WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
# note_watch passes note_path; a file handler passes path; a cron run neither.
NOTE_PATH="${DECREE_DATA_NOTE_PATH:-${DECREE_DATA_PATH:-}}"
NOTE=""
[[ -n "$NOTE_PATH" && -f "${WS}/${NOTE_PATH}" ]] && NOTE="$(head -c 20000 "${WS}/${NOTE_PATH}")"
export NOTE_PATH NOTE

ask() { MODEL_TIMEOUT="${MODEL_TIMEOUT:-300}" model_chat "$1" "$2" 3000; }

automation_run() {
    local name="$1" dir out body
    dir="${WS}/ai/automations/${name}"
    local label; label="$(basename "${NOTE_PATH:-scheduled}" .md)"
    out="${dir}/$(date +%F)-${label}.md"
    mkdir -p "$dir"
    body="$(steps)"
    {
        printf -- '---\nkind: automation-result\nautomation: %s\nnote: %s\ndate: %s\n---\n\n' "$name" "$NOTE_PATH" "$(date -u +%FT%TZ)"
        printf '# %s: %s\n\n' "$name" "$label"
        if [[ -n "$NOTE_PATH" ]]; then printf 'Ran for [%s](../../../%s). ' "$NOTE_PATH" "$NOTE_PATH"; else printf 'Ran on its schedule. '; fi
        printf 'Written by an automation: check it before relying on it.\n\n'
        printf '%s\n' "$body"
    } > "${out}.tmp"
    mv "${out}.tmp" "$out"
    echo "${name}: wrote ${out#"${WS}/"}"
    { printf '%s\n\n' "$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/d' | head -8)"
      printf 'All of it: %s\n' "${out#"${WS}/"}"; } |
        decree emit --machine notify --param ntfy_title="${name}: done" --param ntfy_tags=robot >/dev/null
}
