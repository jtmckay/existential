---
sidebar_position: 3
---

# Hermes

- Source: https://github.com/NousResearch/hermes-agent
- License: [MIT](https://opensource.org/licenses/MIT)

AI agent gateway with an OpenAI-compatible API and a live dashboard.

## Recommended Workflow

| Tool | Use for |
|---|---|
| Hermes dashboard | Sessions, skills, and agent configuration |
| [Open WebUI](./open-web-ui) | Day-to-day conversations |
| opencode | Coding assistant — connect via Hermes gateway as the OpenAI API endpoint |

Configure opencode to point at the Hermes gateway (`https://hermes-agent.<domain>/v1`) with `HERMES_API_KEY` as the API key so all three surfaces share the same models and skills.

## Services

| Container | Purpose | Port |
|---|---|---|
| hermes-agent | Gateway API + dashboard | 48642 (API), 49119 (dashboard) |

## Architecture

`hermes-agent` is the long-running gateway. It exposes an OpenAI-compatible HTTP API on `:8642` and a dashboard on `:9119`. [Open WebUI](./open-web-ui) connects to it over the internal `exist` network.

The `./data` directory is bind-mounted into the container for agent config, sessions, skills, and memory.

### Profiles

With `GATEWAY_MULTIPLEX_PROFILES=1` the gateway serves more than one agent from the same
container. The default profile answers at `/v1`; every other profile lives at `/p/<name>/v1`
with its own `HERMES_HOME` under `/opt/data/profiles/<name>/`, and therefore its own toolsets,
MCP servers and skills.

That separation is what makes routing affordable. A profile's system prompt carries a schema for
every tool it owns — roughly 2.4 KB each — so the default profile's 21 tools cost about 17,000
tokens on every single call. A router that only has to *pick a department* needs no tools at all,
so it runs at about 650 tokens: a 64x reduction on a decision made for every incoming message.

Each profile needs its own `API_SERVER_KEY` — one profile's key will not authenticate against
another, and an unknown profile name returns 404. `./existential.sh run hermes profiles` creates
one profile per `dept-*.sh` routine, reading each department's declared description, toolsets and
MCP servers straight out of its source. It is idempotent, so re-running only fills in what is
missing.

See [Routing to Departments](../decree/routing.md) for how a message reaches the right one.

### Model configuration

The `model:` block in `config.yaml` is kept in step with `.env.shared` — change `EXIST_MODEL_CHAT`
or the chat endpoint and the next `./existential.sh` moves hermes with the rest of the stack.
That only applies while the block still points at a local model server (`provider: custom` and a
`:11434` endpoint). Point it at Anthropic, OpenRouter or anything else and it becomes yours: every
line is left alone from then on, except `context_length`, which is a fact about how the model was
built rather than a preference.

## Authentication

`HERMES_API_KEY` in `ai/hermes/.env.exist` is the shared secret for the gateway. It is the gateway's `API_SERVER_KEY`; Open WebUI sends it as `OPENAI_API_KEY`.

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
```
