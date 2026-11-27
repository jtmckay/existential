---
name: agent_task
x-exist-project: automation
needs:
  - pi
machine:
  description: Hand a task to pi on the local model (a department picks its tools) and file the answer in workspace/ai/, then notify.
  state_files:
    departments: Yours. One file per department (see its README.md), naming the tools and MCP servers a pi run may reach. run reads it.
  data:
    prompt: {type: string, default: ""}
    department: {type: string, default: ""}
    file_path: {type: string, default: ""}
    output_name: {type: string, default: ""}
    agent_timeout: {type: int, default: 900}
  initial: ask
  states:
    ask:
      invoke: agent_task
      transitions: {done: done}
      emits: [notify]
    done: {final: true}
    failed: {final: true}
scripts:
  agent_task.sh: |
    #!/usr/bin/env bash
    # Agent Task
    #
    # Hands a task to pi on the stack's own chat model and files the answer in
    # workspace/ai/.
    #
    # pi runs its own tool loop against the MCP servers pi_configure registered —
    # qmd search, firecrawl web search, playwright — so the prompt does not
    # need to name tools, only to say what it wants. A machine that wants Claude
    # instead uses lib/agent.sh. Repo-editing work belongs to a coding agent on the
    # host, not to this stack.
    #
    # `department` picks which tools it gets (store/agent_task/departments/<name>.yml; empty:
    # pi's defaults and every MCP server).
    #
    # The prompt is the `prompt` param, or else the message body:
    #
    #   decree emit --machine agent_task --param department=research \
    #       --param file_path=notes/decisions.md <<<'What should I do about this?'
    set -euo pipefail

    prompt="$DECREE_DATA_PROMPT"
    if [ -z "$prompt" ]; then
        prompt="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE" | sed '/./,$!d')"
    fi
    department="$DECREE_DATA_DEPARTMENT"
    file_path="$DECREE_DATA_FILE_PATH"
    output_name="$DECREE_DATA_OUTPUT_NAME"
    AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-/workspace/ai}"
    AGENT_NOTIFY="${AGENT_NOTIFY:-true}"

    if [ -z "$prompt" ]; then
        echo "prompt is required: a prompt param, or a message body." >&2
        exit 1
    fi

    # shellcheck source=../../lib/pi.sh
    source ".decree/lib/pi.sh"

    # --- Build the full prompt -------------------------------------------------

    # Said plainly rather than as tool wiring: pi decides for itself when to reach
    # for qmd or the web, and telling it what is available is enough.
    system_prompt="Search this workspace's knowledgebase and the web where your tools
    allow it and it would change the answer, and say plainly where you could not find
    something rather than inventing it. You are not here to edit files: your answer
    is filed for you. Write markdown. Be concrete and brief — no preamble, no
    encouragement."

    full_prompt="${prompt}"

    if [ -n "$file_path" ]; then
        full_prompt="${full_prompt}

    The file this is about is ${file_path}."
    fi

    # --- Run it ----------------------------------------------------------------

    _name="${output_name:-${DECREE_MESSAGE_ID}}"
    # One path component only: a source path in output_name would otherwise escape
    # the output directory, and the whole point of that directory is containment.
    _name="$(basename "$_name")"
    _name="${_name%.md}"
    out="${AGENT_OUTPUT_DIR}/${_name}.md"

    mkdir -p "$AGENT_OUTPUT_DIR"

    echo "Asking pi${department:+ (${department})} (timeout ${DECREE_DATA_AGENT_TIMEOUT}s)..."
    _raw="$(mktemp "${DECREE_RUN_DIR}/agent_task.XXXXXX")"
    trap 'rm -f "$_raw"' EXIT

    PI_TIMEOUT="$DECREE_DATA_AGENT_TIMEOUT" pi_run "$department" "$system_prompt" "$full_prompt" > "$_raw" || true

    if [ ! -s "$_raw" ]; then
        echo "pi${department:+ (${department})} returned nothing." >&2
        echo "Check that EXIST_MODEL_URL is reachable and the chat model can carry a" >&2
        echo "tool-using turn; the run's log has pi's own error above." >&2
        exit 1
    fi

    {
        printf -- '---\n'
        printf 'generated_by: agent_task\n'
        printf 'department: %s\n' "$(jq -rn --arg v "${department:-default}" '$v|@json')"
        printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if [ -n "$file_path" ]; then
            printf 'source_file: %s\n' "$(jq -rn --arg v "$file_path" '$v|@json')"
        fi
        if [ -n "${FILE_MATCH_REASON:-}" ]; then
            printf 'matched_because: %s\n' "$(jq -rn --arg v "$FILE_MATCH_REASON" '$v|@json')"
        fi
        printf -- '---\n\n'
        cat "$_raw"
    } > "$out"

    echo "Wrote ${out}"

    # --- Tell someone ----------------------------------------------------------

    if [ "$AGENT_NOTIFY" = "true" ]; then
        decree emit --machine notify --param ntfy_topic=decree \
            --param ntfy_title="Agent task done — ${_name}" \
            --param ntfy_priority=default --param ntfy_tags=robot >/dev/null <<EOF
    ${FILE_MATCH_REASON:-${prompt}}

    Written to workspace/ai/${_name}.md
    EOF
    fi
state:
  departments/README.md: |
    # departments

    **A department is a file here.** Adding one is adding a file — the same move this
    repo makes for services, plugins, cron jobs and e2e checks. Nothing enumerates them.

    A department is what one [pi](https://pi.dev) run may reach: its built-in tools and
    its MCP servers. `pi_run` (`../pi.sh`) turns the file into pi's `--tools` list, so a
    department that owns no tool pays for none in its prompt.

    ## The file

    `<name>.yml`, three flat keys, all optional except `description`:

    ```yaml
    description: When work should come here — the router reads this to choose.
    tools: read, grep, find, ls
    mcp: qmd, firecrawl
    ```

    `description` is the router's catalog entry, so write it as the answer to *"when
    should work come here?"* rather than as a job title. `tools` are pi's built-ins
    (`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`); `mcp` names servers
    `pi_configure` registers: `qmd`, `firecrawl`, `playwright`, each only
    while its add-on is on. Blank means none.

    No department at all (`agent_task` without `department`) is pi's default tools plus
    every MCP server.

    ## Who reads it

    | Reader | For |
    |---|---|
    | `pi_run` (`../pi.sh`) | the tools and servers of one run |
    | `router` | the catalog it chooses from |

    ## Using one

    ```
    ---
    machine: agent_task
    params:
      department: research
      output_name: competition
    ---
    <the task>
    ```

    `router` emits exactly that message after picking a department. Setup and reference:
    <https://existential.company/docs/plugins/routing>.
  departments/research.yml: |
    # The only department with web access.
    description: Investigation, fact-finding, competitive and market analysis, literature review.
    tools: read, grep, find, ls
    mcp: qmd, firecrawl
  departments/sales.yml: |
    # Anything aimed at winning or keeping a customer.
    description: Outbound, discovery calls, deal strategy, pricing, and customer-facing writing.
    tools: read, grep, find, ls
    mcp: qmd
---
# agent_task

Hand a task to pi on the local model (a department picks its tools) and file the answer in workspace/ai/, then notify.

It needs, on the stack that installs it:

- .decree/lib/pi.sh
