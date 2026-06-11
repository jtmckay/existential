---
sidebar_position: 3
---

# Hermes

- Source: https://github.com/NousResearch/hermes-agent
- Workspace: https://github.com/outsourc-e/hermes-workspace
- License: [MIT](https://opensource.org/licenses/MIT) (both hermes-agent and hermes-workspace)

AI agent gateway with an OpenAI-compatible API, a kanban/terminal workspace UI, and a live dashboard.

## Recommended Workflow

| Tool | Use for |
|---|---|
| Hermes Workspace | Managing skills, profiles, and agent configuration |
| [Open WebUI](./open-web-ui) | Day-to-day conversations |
| opencode | Coding assistant — connect via Hermes gateway as the OpenAI API endpoint |

Configure opencode to point at the Hermes gateway (`http://localhost:48642/v1`) with `HERMES_API_KEY` as the API key so all three surfaces share the same models and skills.

## Services

| Container | Purpose | Port |
|---|---|---|
| hermes-agent | Gateway API + dashboard | 48642 (API), 49119 (dashboard) |
| hermes-workspace | Full UI — swarms, terminal, kanban | 49300 |

## Architecture

`hermes-agent` is the long-running gateway. It exposes an OpenAI-compatible HTTP API on `:8642` and a dashboard on `:9119`. `hermes-workspace` and [Open WebUI](./open-web-ui) both connect to it over the internal `exist` network.

The `./data` directory is bind-mounted into both containers so they share agent config, sessions, skills, and memory.

## Authentication

`HERMES_API_KEY` in `.env.exist` is the shared secret for the gateway. hermes-workspace sends it as `HERMES_API_TOKEN`; Open WebUI sends it as `OPENAI_API_KEY`.

## Upgrading

The `hermes-agent-src` volume caches the agent Python source. After pulling a new image, remove it before restarting:

```bash
docker compose down
docker volume rm hermes_hermes-agent-src
docker compose pull && docker compose up -d
```

## Debugging

```bash
docker compose logs hermes-agent
docker compose logs hermes-workspace
```
