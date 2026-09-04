---
name: Local AI Lab
tagline: Chat with local LLMs, transcribe audio, connect tools to your AI
e2e: true
services:
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama
  - var: EXIST_IS_AI_OPEN_WEBUI
    label: Open WebUI
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_AI_MCP
    label: MCP (Playwright)
  - var: EXIST_IS_AI_FIRECRAWL
    label: Firecrawl
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking
  - var: EXIST_IS_AI_WHISPERX
    label: WhisperX
  - var: EXIST_IS_AI_COMFYUI
    label: ComfyUI
---

After `docker compose up -d`, complete the one-time setup steps below for
each service you enabled.

── Ollama: pull models ────────────────────────────────────────────────────

Models are named ONCE, in the "Model Selection" block in .env.shared —
EXIST_MODEL_CHAT, EXIST_MODEL_EXTRACT, EXIST_MODEL_EMBED, EXIST_MODEL_VISION.
Nothing hardcodes a tag; change them there and everything follows.

Pull whatever those name, right now, in the foreground:
  ./existential.sh run ollama pull-models

Or let Decree do it unattended, in the background, as soon as ollama is
healthy — each migration below pulls (or configures) one role. Same
mechanism Core uses; copy only what this quest actually needs:

  mkdir -p automation/migrations/
  cp automation-examples/migrations/10-ollama-pull-chat-model.md \
     automation-examples/migrations/11-ollama-set-chat-context.md \
     automation-examples/migrations/12-ollama-pull-extract-model.md \
     automation-examples/migrations/13-ollama-pull-embed-model.md \
     automation-examples/migrations/14-ollama-pull-vision-model.md \
     automation/migrations/
  docker compose restart automation

Migrations run once each, in order, the first time decree sees them — no
cron, no restart needed after the first one. At the defaults (~4 GB total)
pulling takes a few minutes. Models are stored in the ollama_cache volume
and survive container restarts.

To pull individual models manually:
  docker exec ollama ollama pull <model>
  docker exec ollama ollama list

── Hermes: already wired ──────────────────────────────────────────────────

./existential.sh seeds hermes' config before the container starts, so on the
first `docker compose up -d` it already points at ollama (EXIST_MODEL_CHAT,
with a matching context_length), has honcho memory enabled, and has the MCP
servers for the AI services you enabled.

Playwright is the exception: hermes seeds firecrawl and openviking only, so
if you enabled MCP you must register it yourself, once, after `up -d`:
  ./existential.sh run mcp mcp           # Playwright — browser automation

Only reach for these if you want to CHANGE the seeded entries — each overwrites:
  ./existential.sh run hermes setup      # interactive model picker (needs a TTY)
  ./existential.sh run firecrawl mcp     # Firecrawl  — web scraping
  ./existential.sh run openviking mcp    # OpenViking — context database

The seeding never overwrites: anything already in config.yaml wins.

If you enabled Hermes, its volume (config + skills) is worth backing up —
nightly by default, weekly optional:

  mkdir -p services/automation/backup/cron/
  cp services/automation/backup/cron.example/hermes-volume-backup-nightly.md \
     services/automation/backup/cron/
  docker compose restart automation-backup

── ComfyUI: download checkpoints ─────────────────────────────────────────

ComfyUI runs at https://comfyui.x.internal after containers are up.
It ships with no models — download one via the ComfyUI Manager node
in the UI, or place .safetensors files directly in:
  volumes/comfyui_data/ComfyUI/models/checkpoints/

Recommended starting model: SDXL base (6.9 GB from civitai.com or HuggingFace).

The comfy-image-* and comfy-video-i2v decree routines need Flux2 and Wan 2.2
instead; the HuggingFace URLs are in each workflow in automation/lib/comfy/,
and they go under .../models/{diffusion_models,text_encoders,vae,loras}/.

── OpenViking: your knowledgebase ────────────────────────────────────────

Your knowledgebase is the workspace/ directory at the repo root — the same
tree hermes and code-server share, so everything you work on is indexed
without a second directory to keep in step. ./existential.sh creates it, but
nothing indexes it until you activate the cron:

  mkdir -p automation/cron/
  cp automation-examples/cron/openviking-index-knowledgebase.md \
     automation/cron/
  docker compose restart automation

That indexes every 15 minutes: workspace/ (including workspace/ai/, the
output of the agent automations, so an agent can find what an earlier run
produced). Subdirectories are preserved. Deleting a file on disk removes it
from the index on the next run.

To index a second directory, copy the same file again under a new name and
give it its own INDEX_DIR and INDEX_PREFIX in the frontmatter.

OpenViking's own volume (the vector index) is worth backing up too:

  cp services/automation/backup/cron.example/openviking-volume-backup-nightly.md \
     services/automation/backup/cron/
  docker compose restart automation-backup
