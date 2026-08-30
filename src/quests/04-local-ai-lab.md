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
  - var: EXIST_IS_AI_CHATTERBOX
    label: Chatterbox
  - var: EXIST_IS_AI_COMFYUI
    label: ComfyUI
copies:
  - src: ai/hermes/decree/cron.example/hermes-volume-backup-nightly.md
    dst: ai/hermes/decree/cron/
    label: "hermes: volume-backup-nightly.md"
    requires: EXIST_IS_AI_HERMES
  - src: ai/hermes/decree/cron.example/hermes-volume-backup-weekly.md
    dst: ai/hermes/decree/cron/
    label: "hermes: volume-backup-weekly.md"
    requires: EXIST_IS_AI_HERMES
  - src: ai/openviking/decree/cron.example/openviking-volume-backup-nightly.md
    dst: ai/openviking/decree/cron/
    label: "openviking: volume-backup-nightly.md"
    requires: EXIST_IS_AI_OPENVIKING
  - src: ai/openviking/decree/cron.example/openviking-volume-backup-weekly.md
    dst: ai/openviking/decree/cron/
    label: "openviking: volume-backup-weekly.md"
    requires: EXIST_IS_AI_OPENVIKING
---

After `docker compose up -d`, complete the one-time setup steps below for
each service you enabled.

── Ollama: pull models ────────────────────────────────────────────────────

Models are named ONCE, in the "Model Selection" block in .env.shared —
EXIST_MODEL_CHAT, EXIST_MODEL_EXTRACT, EXIST_MODEL_EMBED, EXIST_MODEL_VISION.
Nothing hardcodes a tag; change them there and everything follows.

Pull whatever those name:
  ./existential.sh run ollama pull-models

Or let it happen unattended — the auto-ollama-models quest copies migrations
that ollama-decree runs as soon as ollama is healthy.

At the defaults (~4 GB total) this takes a few minutes. Models are stored in
the ollama_data volume and survive container restarts.

To pull individual models manually:
  docker exec ollama ollama pull <model>
  docker exec ollama ollama list

── Hermes: already wired ──────────────────────────────────────────────────

./existential.sh seeds hermes' config before the container starts, so on the
first `docker compose up -d` it already points at ollama (EXIST_MODEL_CHAT,
with a matching context_length), has honcho memory enabled, and has the MCP
servers for the AI services you enabled.

Only reach for these if you want to CHANGE that — each one overwrites:
  ./existential.sh run hermes setup      # interactive model picker (needs a TTY)
  ./existential.sh run mcp mcp           # Playwright — browser automation
  ./existential.sh run firecrawl mcp     # Firecrawl  — web scraping
  ./existential.sh run openviking mcp    # OpenViking — context database

The seeding never overwrites: anything already in config.yaml wins.

── ComfyUI: download checkpoints ─────────────────────────────────────────

ComfyUI runs at https://comfyui.x.internal after containers are up.
It ships with no models — download one via the ComfyUI Manager node
in the UI, or place .safetensors files directly in:
  ai/comfyui/comfyui_data/models/checkpoints/

Recommended starting model: SDXL base (6.9 GB from civitai.com or HuggingFace).

── OpenViking: your knowledgebase ────────────────────────────────────────

Your knowledgebase is the workspace/ directory at the repo root — the same
tree hermes and code-server share, so everything you work on is indexed
without a second directory to keep in step. ./existential.sh creates it and
activates the indexer cron, so there is nothing to set up: the sidecar
uploads new and changed files every 15 minutes, and hermes searches them
through the openviking MCP server.

workspace/ai/ holds the output of the agent automations. It is indexed like
everything else, so an agent can find what an earlier run produced.

Subdirectories are preserved. Deleting a file on disk removes it from the
index on the next run.

To index a second directory, copy
ai/openviking/decree/cron.example/openviking-index-knowledgebase.md to
decree/cron/ under a new name and give it its own INDEX_DIR and
INDEX_PREFIX.
