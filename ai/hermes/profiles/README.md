# hermes profiles

**A profile is a directory here.** Adding one is adding a directory — the same
move this repo already makes for services, quests, cron jobs and e2e checks.
Nothing enumerates them.

A hermes profile is its own `HERMES_HOME`: its own `config.yaml`, `.env`,
`SOUL.md` and `skills/`, served off the one gateway listener at `/p/<name>/v1`
(`GATEWAY_MULTIPLEX_PROFILES: '1'`). The default profile keeps the bare `/v1`.

Why split at all: tool schemas are the expensive axis of a hermes prompt —
roughly 2.4 KB each, against ~76 B for a skill's index entry. The default
profile carries every tool at ~17,000 prompt tokens per call; the tool-free
`router` profile costs ~630. That gap is what makes routing *every* message
through a model affordable.

## The file

`<name>/profile.yml`, three keys, all optional except `description`:

```yaml
description: When work should come here — the router reads this to choose.
toolsets: search, web, skills, todo
mcp: openviking, firecrawl
```

`description` is the router's catalog entry, so write it as the answer to *"when
should work come here?"* rather than as a job title. Blank `toolsets` and `mcp`
mean exactly that: no tools, no MCP servers.

Recognised MCP names are `openviking` and `firecrawl`. An unknown name is
skipped with a warning rather than written out — an MCP entry pointing at
nothing makes hermes retry a dead endpoint on every task.

## Who reads it

| Reader | Reads | For |
|---|---|---|
| `ai/hermes/entrypoint.sh` | this directory, mounted `/opt/profile-defs:ro` | creating the profile on boot |
| `hermes-router` | `/repo/ai/hermes/profiles/*/profile.yml` | the catalog it chooses from |

Both read the same file, so a description is written once.

## What is generated, and what is never tracked

The definition is declarative and public. Everything secret is generated at boot
into `volumes/hermes_agent_data/profiles/<name>/`:

- **`API_SERVER_KEY`** — each profile gets its own. A secondary profile does not
  borrow the default profile's credential: without one it returns 401 on every
  request, and an unknown profile name returns 404 rather than quietly falling
  through to the default.
- **MCP credentials** — resolved from the container's environment.
- **The `model:` block** — copied from the default profile's `config.yaml`, so
  the stack's single model choice stays a single choice (CLAUDE.md: *model
  choice is global, never per-service*). Change it with `hermes model` and
  restart.

## Provisioning

`ai/hermes/entrypoint.sh` does it on every boot, before the gateway starts —
which is the only place that *can*, per CLAUDE.md rule 6: the hermes CLI lives
inside this container and the profiles live in its data volume, so neither the
host nor a decree migration can reach them (decree has no Docker socket and
sees the repo read-only).

Idempotent and never destructive: an existing profile keeps its `config.yaml`.
To rebuild one after editing its definition, delete
`volumes/hermes_agent_data/profiles/<name>` and restart hermes.

Profiles start with **no agents** (`--no-skills`) on purpose. Install the ones
you want into `volumes/hermes_agent_data/profiles/<name>/skills/`.

## Using one

Work is dispatched by the single `hermes-dept` routine, which takes the profile
as a message parameter:

```
---
routine: hermes-dept
profile: research
output_name: competition
---
<the task>
```

`hermes-router` writes exactly that message after picking a department. Setup
guide: the **Hermes Departments** quest. Deeper reference:
<https://existential.company/docs/decree/routing>.
