---
machine: plugin
automation: pi
needs:
  - model
lib:
  pi.sh: |
    #!/usr/bin/env bash
    # pi.sh — pi (https://pi.dev) on the stack's own chat model, with tools.
    #
    # Sourced, never run. model.sh is one answer from the chat role's /v1 URL;
    # agent.sh is Claude Code; this is the third way to reach a model: an agent
    # with tools that answers from the local model, so nothing leaves the box.
    #
    #   source "${DECREE_LIB}/pi.sh"
    #
    #   pi_configure                       write pi's provider and MCP servers (entrypoints)
    #   pi_run <department> <system> <prompt>   the answer on stdout; "" = every tool
    #
    # A department is a file in lib/departments/ (see its README): the tools and MCP
    # servers it gets. pi is baked into the decree image, so code-server's terminal
    # has the same CLI, configured by the same pi_configure.

    # shellcheck source=model.sh
    source "$(dirname "${BASH_SOURCE[0]}")/model.sh"

    PI_DEPARTMENTS="${PI_DEPARTMENTS:-$(dirname "${BASH_SOURCE[0]}")/departments}"

    # pi_configure — the "existential" provider (the chat role's URL and tag) in
    # models.json, and the MCP servers of every enabled add-on in mcp.json. Both are
    # merged into what is there, so a provider or server a person adds survives; ours
    # are rewritten every boot, so a changed endpoint or a disabled add-on follows.
    pi_configure() {
        local dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}" f
        mkdir -p "$dir"
        for f in models.json mcp.json settings.json; do
            [[ -s "$dir/$f" ]] || echo '{}' > "$dir/$f"
        done

        jq --arg url "$(model_url chat)" --arg model "${EXIST_MODEL_CHAT:-}" \
           --argjson ctx "${EXIST_MODEL_CHAT_NUM_CTX:-65536}" '
            .providers.existential = {
                baseUrl: $url, api: "openai-completions", apiKey: "none",
                models: [{id: $model, input: ["text", "image"], contextWindow: $ctx}]
            }' "$dir/models.json" > "$dir/models.json.tmp" && mv "$dir/models.json.tmp" "$dir/models.json"

        # direct: each tool declared like a built-in. A local model calls a declared
        # tool far more reliably than it writes a codemode script to find one.
        jq --arg fc "${EXIST_IS_AI_FIRECRAWL:-false}" \
           --arg pw "${EXIST_IS_AI_MCP:-false}" --arg qmd "${EXIST_IS_AI_QMD:-false}" '
            def server(on; s): if on then s + {exposure: "direct"} else null end;
            .mcpServers = ((.mcpServers // {}) + {
                firecrawl:  server($fc == "true"; {url: "http://firecrawl-mcp:3003/mcp"}),
                playwright: server($pw == "true"; {url: "http://mcp-playwright:8931/mcp"}),
                qmd:        server($qmd == "true"; {url: "http://qmd:8181/mcp"})
            } | with_entries(select(.value != null)))
            ' "$dir/mcp.json" > "$dir/mcp.json.tmp" && mv "$dir/mcp.json.tmp" "$dir/mcp.json"

        # Telemetry ships off; the stack's model is the default for a bare `pi`.
        jq --arg model "${EXIST_MODEL_CHAT:-}" '.enableInstallTelemetry = false
            | .defaultProvider //= "existential" | .defaultModel //= $model' \
            "$dir/settings.json" > "$dir/settings.json.tmp" && mv "$dir/settings.json.tmp" "$dir/settings.json"
    }

    # One key of a department file. Flat keys on purpose, so grep is enough.
    _pi_dept_key() {
        grep -m1 "^${2}:" "$1" | sed "s/^${2}:[[:space:]]*//; s/[[:space:]]*$//"
    }

    # pi_run <department> <system> <prompt> — one pi run in the workspace, no session
    # kept. An empty department gets pi's default tools and every MCP server.
    pi_run() {
        local dept="$1" system="$2" prompt="$3" def tools mcp s
        local -a args=()
        if [[ -n "$dept" ]]; then
            def="${PI_DEPARTMENTS}/${dept}.yml"
            if [[ ! -f "$def" ]]; then
                echo "pi: no department '${dept}' (lib/departments/${dept}.yml)" >&2
                return 1
            fi
            tools="$(_pi_dept_key "$def" tools | tr -d ' ')"
            mcp="$(_pi_dept_key "$def" mcp | tr -d ' ')"
            for s in ${mcp//,/ }; do tools+="${tools:+,}mcp__${s}__*"; done
            if [[ -z "$tools" ]]; then args+=(--no-tools); else args+=(--tools "$tools"); fi
            # --tools keeps every MCP tool unless it names one, so none means off.
            [[ -z "$mcp" ]] && args+=(--no-mcp)
        fi
        ( cd "${AUTOMATIONS_WORKSPACE:-/workspace}" \
            && timeout "${PI_TIMEOUT:-900}" pi -p --no-session --offline \
                --provider existential --model "${EXIST_MODEL_CHAT:-}" "${args[@]}" \
                --append-system-prompt "$system" -- "$prompt" )
    }
  departments/README.md: |
    # departments

    **A department is a file here.** Adding one is adding a file — the same move this
    repo makes for services, flows, cron jobs and e2e checks. Nothing enumerates them.

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
    <https://existential.company/docs/decree/routing>.
  departments/research.exist.yml: |
    # The only department with web access.
    description: Investigation, fact-finding, competitive and market analysis, literature review.
    tools: read, grep, find, ls
    mcp: qmd, firecrawl
  departments/sales.exist.yml: |
    # Anything aimed at winning or keeping a customer.
    description: Outbound, discovery calls, deal strategy, pricing, and customer-facing writing.
    tools: read, grep, find, ls
    mcp: qmd
---
# pi

pi with tools on the stack's own chat model, nothing leaving the box: pi_run and pi_configure (${DECREE_LIB}/pi.sh). A department, departments/<name>.yml, is what one run may reach; the two here are examples, copied once to yours.
