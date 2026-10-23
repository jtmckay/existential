---
name: Local AI
tagline: Ollama serving the models, Hermes as the agent, Honcho for memory, OpenViking for your material
e2e: false
services:
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama (local models)
  - var: EXIST_IS_AI_HERMES
    label: Hermes (the agent)
  - var: EXIST_IS_AI_HONCHO
    label: Honcho (agent memory)
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking (context database)
  - var: EXIST_IS_AI_FIRECRAWL
    label: Firecrawl (web crawler for the agent)
done:
  files:
    - automation/migrations/10-ollama-pull-chat-model.md
    - automation/migrations/11-ollama-set-chat-context.md
    - automation/migrations/12-ollama-pull-extract-model.md
    - automation/migrations/13-ollama-pull-embed-model.md
    - automation/migrations/14-ollama-pull-vision-model.md
    - automation/cron/openviking-index-knowledgebase.md
    - automation/cron/note-connect.md
---

A model server, an agent in front of it, memory that survives the session, and
an index of your own material for it to answer from.

Core does not install any of it: GPU models usually run on another machine.
Do this on the box with the card, or point EXIST_OLLAMA_URL at one. The model
rules below are the ones people get wrong.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_AI_OLLAMA=true
       EXIST_IS_AI_HERMES=true
       EXIST_IS_AI_HONCHO=true
       EXIST_IS_AI_OPENVIKING=true
       EXIST_IS_AI_FIRECRAWL=true

       ./existential.sh
       docker compose up -d

Already have an ollama on another machine? Answer the GPU question with
"models live elsewhere" (`./existential.sh run models`) — the local ollama
stays off and everything follows EXIST_OLLAMA_URL instead.

── 2. Pull the models ────────────────────────────────────────────────────

Models are named **once**, in the *Model Selection* block in `.env.shared`.
Nothing in this repo hardcodes a tag; change it there and everything follows.

Foreground, right now:

       ./existential.sh run ollama pull-models

Or let decree do it unattended as soon as ollama is healthy — one migration
per role, each running exactly once:

       mkdir -p automation/migrations/
       cp automation-examples/migrations/10-ollama-pull-chat-model.md \
          automation-examples/migrations/11-ollama-set-chat-context.md \
          automation-examples/migrations/12-ollama-pull-extract-model.md \
          automation-examples/migrations/13-ollama-pull-embed-model.md \
          automation-examples/migrations/14-ollama-pull-vision-model.md \
          automation/migrations/

Those migrations name a **role**, never a tag:

  chat      EXIST_MODEL_CHAT — the agent's brain. Hermes uses it for every
            task, so it MUST have ollama's "tools" badge.
  chat-ctx  Rebuilds the chat model with num_ctx=EXIST_MODEL_CHAT_NUM_CTX,
            same tag. Hermes needs 64k for its system prompt; ollama's stock
            4096–8192 truncates it silently, which reads as the model
            ignoring its instructions.
  extract   EXIST_MODEL_EXTRACT — Honcho's deriver, dialectic and summaries.
            Defaults to the same tag as chat so a small card holds one model.
  embed     EXIST_MODEL_EMBED — OpenViking's vector store. Do NOT change it
            after the first ingestion; mismatched dimensions corrupt the index.
  vision    EXIST_MODEL_VISION — image OCR and image chat. Defaults to the
            chat tag, because every tier model is multimodal; the migration
            skips itself when the key is blank.

Check what landed:  `docker exec ollama ollama list`

── 3. Hermes is already wired ────────────────────────────────────────────

`./existential.sh` seeds hermes' config before the container starts, so the
first `docker compose up -d` already points it at ollama with a matching
context length, enables Honcho memory, and registers the MCP servers for the
AI services you enabled. Seeding never overwrites — anything already in
config.yaml wins.

Only reach for these if you want to CHANGE a seeded entry (each overwrites):

       ./existential.sh run hermes setup      # interactive model picker (needs a TTY)
       ./existential.sh run firecrawl mcp     # Firecrawl  — web scraping
       ./existential.sh run openviking mcp    # OpenViking — context database
       ./existential.sh run mcp mcp           # Playwright — only if you enabled MCP

Talk to it from a terminal: `hermes` inside code-server, or the gateway over
HTTP at https://hermes.${EXIST_DOMAIN}. No container installs a second AI CLI —
the gateway is the one way to reach a model.

── 4. Memory: confirm Honcho took ────────────────────────────────────────

       docker exec -it hermes-agent hermes memory status

It should name the Honcho provider at `http://honcho:8000`. If it does not
(Honcho came up after hermes, say), run the wizard once — backend `local`, URL
`http://honcho:8000`, blank JWT secret:

       docker exec -it hermes-agent hermes memory setup honcho

Built-in memory (MEMORY.md / USER.md) stays active alongside it. Only one
external provider can be active at a time; `hermes memory off` switches back.

── 5. Index your own material ────────────────────────────────────────────

OpenViking is installed empty. Without the cron below, hermes answers from the
model alone and the "it knows your material" half of this quest is inert. The
knowledgebase is `workspace/` — the same tree code-server and hermes share, so
there is no second directory to keep in step.

       mkdir -p automation/cron/
       cp automation-examples/cron/openviking-index-knowledgebase.md \
          automation/cron/

       # Surfaces connections between what you just wrote and what you already
       # know, hourly. Needs the index above.
       cp automation-examples/cron/note-connect.md automation/cron/

Indexing runs every 15 minutes and preserves subdirectories; deleting a file on
disk drops it from the index on the next run. To index a second directory, copy
the same cron under a new name with its own INDEX_DIR and INDEX_PREFIX.

── 6. Check it ───────────────────────────────────────────────────────────

       ./existential.sh test ollama hermes honcho openviking firecrawl

── What to build on this ─────────────────────────────────────────────────

**Hermes Departments** (cheap specialists + a router), **Workspace Agent**
(edit a file, an agent does the work), **Note Triage**, **Hermes Spotify**.
Backups for the hermes and openviking volumes: the **Backups** quest.
Image generation is a separate service — the **ComfyUI** quest.
