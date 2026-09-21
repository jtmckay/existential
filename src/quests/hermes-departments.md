---
name: Hermes Departments
tagline: Split the agent into cheap specialists and route work to the right one
e2e: false
services:
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

One hermes container can serve more than one agent. Each is a profile: its own
HERMES_HOME with its own config.yaml, .env, SOUL.md and skills/ — and therefore
its own toolset. GATEWAY_MULTIPLEX_PROFILES is already on, so every profile
answers at /p/<name>/v1 off the same listener the default profile serves at /v1.

Why bother: a profile's system prompt carries a schema for every tool it owns,
roughly 2.4 KB each. The default profile's 21 tools cost about 17,000 prompt
tokens on every call. The tool-free router profile costs about 630. That gap is
the whole feature — routing every message through a model is only affordable
when the model doing the routing carries no tools.

Ships with three profiles, in ai/hermes/profiles/:
  router      reads a task, names the department, stops. No tools, no MCP.
  research    investigation, fact-finding, competitive and market analysis
              (search, web, skills, todo + openviking, firecrawl)
  sales       outbound, discovery calls, deal strategy, pricing, customer-facing
              writing (skills, todo + openviking)

Docs: https://existential.company/docs/decree/routing

── 1. The profiles provision themselves ──────────────────────────────────

Nothing to run. ai/hermes/entrypoint.sh creates every profile declared in
ai/hermes/profiles/ when the container starts, so the three above already
exist. Check:

  docker exec hermes-agent ls /opt/data/profiles

If that is empty, restart hermes — the profiles are created on boot:

  docker compose up -d hermes-agent

It is idempotent and never destructive: an existing profile keeps its
config.yaml. To rebuild one after editing its definition, delete
volumes/hermes_agent_data/profiles/<name> and restart.

Each profile gets its OWN API_SERVER_KEY. A secondary profile does not borrow
the default profile's credential — without one it returns 401 on every request,
and an unknown profile name returns 404 rather than quietly falling through to
the default.

── 2. Enable the routines ────────────────────────────────────────────────

In services/automation/decree/config.yml:

  hermes-router:
    enabled: true
  hermes-dept:
    enabled: true

There is one hermes-dept for every department — which one is a message
parameter, not a routine of its own. Add idea-workup too if you want the
fan-out path; it hands one idea to research and sales at once and writes each
answer into workspace/ai/:

  idea-workup:
    enabled: true

Restart decree so it re-reads the whitelist.

── 3. Verify ─────────────────────────────────────────────────────────────

What a profile costs:

  docker exec -e HERMES_HOME=/opt/data/profiles/research hermes-agent \
    /opt/hermes/.venv/bin/hermes prompt-size

And route something. Drop this in automation/inbox/:

  ---
  routine: hermes-router
  ---
  Who else is already selling a self-hosted homelab bundle?

The router picks a department and queues hermes-dept for it; the answer lands
in workspace/ai/ and ntfy tells you it arrived.

── Adding your own department ────────────────────────────────────────────

Adding a department is adding a directory. Create
ai/hermes/profiles/<name>/profile.yml:

  description: When work should come here — the router reads this to choose.
  toolsets: search, web, skills, todo
  mcp: openviking, firecrawl

Then restart hermes. That is the whole job: entrypoint.sh provisions the new
profile, and hermes-router reads the same file to build the catalog it chooses
from — so the description is written once and both sides pick it up. No routine
to write, nothing to enable, nothing here to edit.

Write the description as the answer to "when should work come here?" rather
than as a job title; it is what the router is choosing between.

Full contract: ai/hermes/profiles/README.md

── Notes ─────────────────────────────────────────────────────────────────

- Profiles start with no agents on purpose (--no-skills). Install the ones you
  want into volumes/hermes_agent_data/profiles/<name>/skills/. Skills cost
  ~76 B each in the always-on index; tool schemas cost ~2.4 KB, which is why
  the toolset list is the thing kept short.
- A profile inherits its model from your default profile, so the stack's single
  model choice stays a single choice.
- Address a department directly and skip the router entirely with
  `routine: hermes-dept` + `profile: research` in a message.
- An unroutable message goes to route-failed, which logs and stops. The router
  never guesses.
- The note-triage quest's idea-workup path depends on these profiles.
