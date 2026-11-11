---
sidebar_position: 3
---

# pi

- Source: https://github.com/earendil-works/pi
- Site: https://pi.dev
- License: [MIT](https://opensource.org/licenses/MIT)

A small agent with tools (read, bash, edit, write, grep, find, ls and MCP) that runs against the
stack's own chat model, so the work stays on your box.

pi is not a service and has no flag or container. It is a pinned CLI baked into the decree
image, so it is in two places:

| Where | Use for |
|---|---|
| [code-server](../services/code-server)'s terminal | `pi` for the TUI, `pi -p "…"` for one answer |
| [decree](../decree/) machines | `agent_task`, `router`, `note_connect`: work with nobody present, the answer filed in `workspace/ai/` |

## What it talks to

`pi_configure` (`workspace/.decree/lib/pi.sh`) writes pi's config on every boot of the `automation`
daemon and of code-server:

- **`models.json`**: an `existential` provider at the chat role's `/v1` URL (`EXIST_MODEL_URL_CHAT`,
  else `EXIST_MODEL_URL`) with `EXIST_MODEL_CHAT` and its context window. A bare `pi` starts on it.
- **`mcp.json`**: the MCP server of every add-on that is on: [OpenViking](./openviking),
  [Firecrawl](./firecrawl), [MCP](./mcp) (Playwright) and [qmd](./qmd). Turn an add-on off and its
  server is gone on the next boot. OpenViking's key stays in the environment, not in the file.
- **`settings.json`**: install telemetry off.

Each is merged into what is there, so a provider you add, a server you add or a `/login` to a hosted
provider in code-server survives. In code-server the files live on the volume
(`PI_CODING_AGENT_DIR=/code-server-data/home/.pi/agent`); in `automation`, under its `/data`.

## Departments

A machine runs pi in a **department**: a file in `workspace/.decree/lib/departments/` naming the tools and
MCP servers that run may reach. A department that needs no web gets no web, and pays for no tool
it does not own.

```yaml
# workspace/.decree/lib/departments/research.yml
description: Investigation, fact-finding, competitive and market analysis, literature review.
tools: read, grep, find, ls
mcp: openviking, firecrawl
```

No department means pi's default tools and every MCP server. See
[Routing to Departments](../decree/routing.md) for how a message picks one.

## Upgrading

The version is `PI_VERSION` in `services/automation/decree/Dockerfile`. Bump it, run
`./existential.sh` (it rebuilds the decree image when its build context changes), then
`docker compose up -d`. Nothing updates pi at runtime.
