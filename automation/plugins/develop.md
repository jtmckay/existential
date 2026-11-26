---
name: develop
x-exist-project: automation
needs:
  - agent
  - firecrawl
  - model
machine:
  description: Build an automation from its accepted spec (notes/automations/<name>.md) as one plugin file - the machine, its script and its trigger - checked by decree check, and offer it in ai/proposed/ for you to read and install. It installs nothing.
  data:
    # From the migration's frontmatter, which automation_propose writes.
    automation: {type: string, default: ""}
    from: {type: string, default: ""}
  initial: develop
  states:
    develop:
      # The second attempt is shown what failed the first: one fix round, then you are told.
      invoke:
        script: {name: develop, attempts: 2}
      transitions: {done: done}
      emits: [notify]
    done: {final: true}
    failed: {final: true}
scripts:
  develop.sh: |
    #!/usr/bin/env bash
    # develop — build one automation from its spec, as an offer.
    #
    # The spec (notes/automations/<name>.md, filed by reconcile) says what is true
    # once the automation exists. Claude (lib/agent.sh) reads it when this
    # container is signed in, the chat model when not, and answers with the trigger,
    # as one JSON line, and the `steps` function; this writes the rest from fixed
    # templates, as ONE PLUGIN FILE:
    #   machine, scripts one state, invoking lib/automations/run.sh + steps
    #   the trigger      note: `x-exist-when:`, which note_watch matches notes against
    #                    file: an `x-exist-handlers:` entry
    #                    cron: a `cron:` file
    # Nothing is installed here. The plugin is installed into a scratch copy of this
    # project to pass decree check, then written to ai/proposed/<name>.md, and you are
    # told where to read it and how to install it (move it into .decree/plugins/).
    # A failed gate keeps its errors for the second attempt; the second failure ends
    # the run, which reaches your phone like any failed run.
    set -euo pipefail
    # shellcheck source=../../lib/model.sh
    source ".decree/lib/model.sh"
    # shellcheck source=../../lib/plugin.sh
    source ".decree/lib/plugin.sh"
    # shellcheck source=../../lib/firecrawl.sh
    source ".decree/lib/firecrawl.sh"
    # shellcheck source=../../lib/agent.sh
    source ".decree/lib/agent.sh"

    # automation_propose writes these at the top of the frontmatter, where decree
    # passes nothing to the run (only params: become DECREE_DATA_*): read them there.
    fm() { yq --front-matter=extract -r ".$1 // \"\"" "$DECREE_MESSAGE"; }
    name="${DECREE_DATA_AUTOMATION:-$(fm automation)}" from="${DECREE_DATA_FROM:-$(fm from)}"
    [[ -n "$name" ]] || { echo "develop: the migration names no automation" >&2; exit 1; }
    [[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "develop: '${name}' is not a machine name" >&2; exit 1; }
    # Only an automation develop built before (and you accepted) is ever offered again.
    if [[ -e ".decree/machines/${name}/machine.yml" ]] && ! grep -qF "Built by develop from notes/automations/${name}.md" ".decree/plugins/${name}.md" 2>/dev/null; then
        echo "develop: ${name} is a machine this stack ships; refusing to offer one by its name" >&2; exit 1
    fi
    WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
    spec="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; next} !f' "$DECREE_MESSAGE")"
    errors="${DECREE_RUN_DIR}/gate.err"

    system='You build one automation from its spec. Reply with exactly two parts and nothing else:
    Line 1: TRIGGER: <one JSON object>, one of
      {"kind": "note", "when": "the kind of note of theirs that is the event, in plain words"}
      {"kind": "file", "match": "a glob relative to the workspace", "changes": ["created"], "quiet": 30}
      {"kind": "cron", "cron": "minute hour day-of-month month day-of-week"}
    Then the bash function, starting "steps() {", no fences.
    steps runs under set -euo pipefail. It has $NOTE_PATH and $NOTE (the note or file that
    started it; empty on a schedule), ask "<instructions>" "<input>" (prints one answer from a
    language model), curl and jq. It prints its results as Markdown, one "## " heading per
    step. A step needing the person becomes a "## For you" item. It never writes or deletes
    files, never reads /secrets, never sends data anywhere but ask, agent and public read-only APIs.
    A file trigger never matches ai/, .decree/ or notes/automations/.'
    if firecrawl_on; then system+='
    It can read the web: web_search "<query>" [n] prints the top n results (default 5), each
    page'"'"'s text in a <source url="..."> tag, and web_read <url> prints one page. Search several angles, then
    give ask the sources with an instruction to use only them, say so when there are none, and cite each claim'"'"'s URL:
        sources="$(web_search "<query>" 5; web_search "<another angle>" 5)"
        echo "## <step>"; ask "<instructions>. Use only the sources below; cite URLs." "$NOTE

    $sources"
    A step whose answer the person will act on (build it or not, buy it or not) comes first,
    as "## Verdict", so it is what reaches their phone.'
    else system+='
    There is no web search: a step that needs the web says, in "## For you", where to look.'
    fi
    if agent_ready; then system+='
    For a step that has to look through the person'"'"'s files or reason at length, agent "<task>" prints
    the answer of Claude Code, which can read and search the workspace but changes nothing.'
    fi
    user="The spec:
    ${spec}"
    [[ -s "$errors" ]] && user+="

    Your last answer failed these checks; fix them:
    $(cat "$errors")"

    if agent_ready; then
        reply="$(agent "${system}

    ${user}" | sed '/^```/d')" || { echo "develop: no answer from Claude" >&2; exit 1; }
    else
        reply="$(MODEL_TIMEOUT=300 model_chat "$system" "$user" 2500 | sed '/^```/d')" || { echo "develop: no answer from the model" >&2; exit 1; }
    fi
    trigger="$(sed -n 's/^TRIGGER: *//p' <<<"$reply" | head -1)"
    # From "steps() {" to its closing "}", so a word after the function is no part of it.
    code="$(awk '/^steps\(\) *\{/{f=1} f{print} f && /^}$/{exit}' <<<"$reply")"

    # ── The gate, before anything is written ─────────────────────────────────────
    fails=()
    kind="$(jq -r '.kind // ""' <<<"$trigger" 2>/dev/null || true)"
    case "$kind" in
        note) [[ -n "$(jq -r '.when // ""' <<<"$trigger")" ]] || fails+=("a note trigger needs 'when'") ;;
        file) match="$(jq -r '.match // ""' <<<"$trigger")"
              [[ -n "$match" ]] || fails+=("a file trigger needs 'match'")
              [[ "$match" == ai/* || "$match" == .decree/* || "$match" == notes/automations/* || "$match" == '**'* ]] &&
                  fails+=("the file trigger '${match}' would match its own output or decree's files")
              jq -e '(.changes // ["created"]) - ["created","modified","deleted"] | length == 0' <<<"$trigger" >/dev/null ||
                  fails+=("changes must be created, modified or deleted") ;;
        cron) [[ "$(jq -r '.cron // ""' <<<"$trigger" | wc -w)" == 5 ]] || fails+=("a cron trigger needs five fields") ;;
        *)    fails+=("line 1 must be TRIGGER: with kind note, file or cron (got: ${trigger:-nothing})") ;;
    esac
    if [[ "$code" != steps\(\)* ]]; then fails+=("no steps() function after the TRIGGER line")
    elif ! err="$(bash -n <<<"$code" 2>&1)"; then fails+=("the steps function does not parse: ${err}"); fi
    firecrawl_on || ! grep -qE '\bweb_(search|read)\b' <<<"$code" || fails+=("web_search and web_read need Firecrawl, which is off")
    agent_ready || ! grep -qE '\bagent\b' <<<"$code" || fails+=("agent needs Claude signed in here, and it is not")
    fail_gate() {
        printf -- '- %s\n' "${fails[@]}" > "$errors"
        echo "develop: ${name} failed the gate:" >&2; cat "$errors" >&2
        exit 1
    }
    [[ ${#fails[@]} -eq 0 ]] || fail_gate

    # ── The plugin file ──────────────────────────────────────────────────────────
    plugin="${DECREE_RUN_DIR}/${name}.md"
    desc="$(sed -n 's/^# //p' <<<"$spec" | head -1)"
    script="$(printf '#!/usr/bin/env bash\n# Built by develop from notes/automations/%s.md. Edit that file, not this one.\n' "$name"
              printf '# shellcheck source=../../lib/automations/run.sh\nsource ".decree/lib/automations/run.sh"\n\n'
              printf '%s\n\nautomation_run %s\n' "$code" "$name")"
    n="$name" d="${desc:-$name}" s="$script" yq -n '
        .name = strenv(n) | .needs = ["develop"] |
        .machine = {"description": strenv(d),
                  "data": {"note_path": {"type": "string", "default": ""}, "path": {"type": "string", "default": ""}, "change": {"type": "string", "default": ""}},
                  "initial": "run",
                  "states": {"run": {"invoke": strenv(n), "transitions": {"done": "done"}, "emits": ["notify"]},
                             "done": {"final": true}, "failed": {"final": true}}} |
        .scripts[strenv(n) + ".sh"] = strenv(s) | .["x-exist-project"] = "automation"' > "${plugin}.yml"
    case "$kind" in
        note) w="$(jq -r .when <<<"$trigger")" yq -i '.["x-exist-when"] = strenv(w)' "${plugin}.yml" ;;
        file) h="$(jq -c '[{match: .match, changes: (.changes // ["created"]), quiet: (.quiet // 30)}]' <<<"$trigger")" yq -i '.["x-exist-handlers"] = (strenv(h) | from_json)' "${plugin}.yml" ;;
        cron) n="$name" c="$(printf -- '---\ncron: "%s"\nmachine: %s\n---\n\nBuilt by develop from notes/automations/%s.md.' "$(jq -r .cron <<<"$trigger")" "$name" "$name")" \
                  yq -i '.cron[strenv(n) + ".md"] = strenv(c)' "${plugin}.yml" ;;
    esac
    { printf -- '---\n'; cat "${plugin}.yml"; printf -- '---\n# %s\n\n%s\n\nBuilt by develop from notes/automations/%s.md%s. To change it, edit that file: develop offers it again.\n' \
        "$name" "${desc:-$name}" "$name" "${from:+ (asked for in ${from})}"; } > "$plugin"

    # ── decree check, in a scratch copy of this project with the plugin installed ──
    if ! plugin_try "$plugin" 2> "${DECREE_RUN_DIR}/install.err"; then
        fails=("$(paste -sd ';' "${DECREE_RUN_DIR}/install.err" | cut -c1-600)")
        fail_gate
    fi
    rm -f "$errors"

    # ── The offer ────────────────────────────────────────────────────────────────
    mkdir -p "${WS}/ai/proposed"
    cp "$plugin" "${WS}/ai/proposed/${name}.md"
    case "$kind" in
        note) starts="when you write a note that is: $(jq -r .when <<<"$trigger")" ;;
        file) starts="when a file matching $(jq -r .match <<<"$trigger") changes" ;;
        cron) starts="on the schedule $(jq -r .cron <<<"$trigger")" ;;
    esac
    echo "develop: built ${name}, which would start ${starts}; offered in ai/proposed/${name}.md"
    { printf '%s is built and waits for you. It would start %s, and write its results to ai/automations/%s/.\n\n' "$name" "$starts" "$name"
      plugin_offered "$name"; } |
        decree emit --machine notify --param ntfy_topic=decree --param ntfy_title="Automation ready to review" --param ntfy_tags=robot >/dev/null
x-exist-lib:
  automations/run.sh: |
    #!/usr/bin/env bash
    # automations/run.sh — the frame every accepted automation runs in.
    #
    # Sourced by the script of every plugin the workspace's develop machine builds
    # from an accepted automation's spec: this file, then the `steps`
    # function the model wrote, then `automation_run <name>`. Everything but `steps`
    # is here, the same for every automation.
    #
    # steps() gets the file that triggered it, if any, and prints its results as
    # Markdown:
    #   NOTE_PATH   the note or file, relative to the workspace; empty on a schedule
    #   NOTE        its text; empty on a schedule
    #   ask <instructions> <input>   one answer from the chat model
    #   agent <prompt>               Claude Code, reading the workspace (agent.sh); only
    #                                when it is signed in, which develop checks
    #   web_search <query> [n]       the top n web results with their pages' text,
    #   web_read <url>               and one page, both through Firecrawl (firecrawl.sh)
    # automation_run writes what steps printed to workspace/ai/automations/<name>/
    # and sends its first lines to ntfy.
    set -euo pipefail
    # shellcheck source=../model.sh
    source ".decree/lib/model.sh"
    # shellcheck source=../firecrawl.sh
    source ".decree/lib/firecrawl.sh"
    # shellcheck source=../agent.sh
    source ".decree/lib/agent.sh"

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
            decree emit --machine notify --param ntfy_topic=decree --param ntfy_title="${name}: done" --param ntfy_tags=robot >/dev/null
    }
---
# develop

Build an automation from its accepted spec (notes/automations/<name>.md) as one plugin file, checked by decree check, and offer it in ai/proposed/ for you to read and install. It installs nothing: moving it into `.decree/plugins/` and `decree install <name>` does.
