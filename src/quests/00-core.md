---
name: Core
tagline: The whole system, wired together — files, house, agent, memory, voice
e2e: false
e2e_skip: Pulls multi-GB LLM, whisper and piper models; too heavy for CI
services:
  - var: EXIST_IS_HOSTING_CADDY
    label: Caddy (TLS + hostnames)
  - var: EXIST_IS_SERVICES_DASHY
    label: Dashy (the dashboard — links to everything below)
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files)
  - var: EXIST_IS_NAS_REDIS
    label: Redis (Nextcloud cache — required by Nextcloud)
  - var: EXIST_IS_NAS_MINIO
    label: MinIO (S3 + file events)
  - var: EXIST_IS_SERVICES_HOMEASSISTANT
    label: Home Assistant (the house)
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree (automation engine)
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama (local models)
  - var: EXIST_IS_AI_HERMES
    label: Hermes (the agent)
  - var: EXIST_IS_AI_OPEN_WEBUI
    label: Open WebUI (the chat window onto Hermes)
  - var: EXIST_IS_AI_HONCHO
    label: Honcho (agent memory)
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking (context database)
  - var: EXIST_IS_AI_FIRECRAWL
    label: Firecrawl (web crawler for the agent)
  - var: EXIST_IS_AI_WYOMING_WHISPER
    label: wyoming-whisper (speech to text)
  - var: EXIST_IS_AI_WYOMING_PIPER
    label: wyoming-piper (text to speech)
copies:
  # Ollama models. Without these migrations ollama starts with NO models and
  # every other AI service fails its first request — the single most common
  # "I enabled it and nothing works" cause.
  - src: ai/ollama/decree/migrations.example/01-pull-chat-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the chat model (EXIST_MODEL_CHAT)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/02-set-chat-context.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: apply the chat context window (EXIST_MODEL_CHAT_NUM_CTX)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/03-pull-extract-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the extraction model (EXIST_MODEL_EXTRACT)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/04-pull-embed-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the embedding model (EXIST_MODEL_EMBED)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/05-pull-vision-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the vision model (skips when EXIST_MODEL_VISION is blank)"
    requires: EXIST_IS_AI_OLLAMA
  # OpenViking watches notes/ and resources/ so hermes and firecrawl have
  # somewhere to put what they read.
  - src: ai/openviking/decree/migrations.example/01-watch-notes.md
    dst: ai/openviking/decree/migrations/
    label: "openviking: watch notes/ and resources/"
    requires: EXIST_IS_AI_OPENVIKING
  # MinIO's bucket for nextcloud's /S3 folder. Without it the external storage
  # mount points at a bucket that does not exist.
  - src: nas/minio/decree/migrations.example/01-create-nextcloud-bucket.md
    dst: nas/minio/decree/migrations/
    label: "minio: create the nextcloud bucket"
    requires: EXIST_IS_NAS_MINIO
  - src: services/decree/decree/cron.example/clean-runs.md
    dst: services/decree/decree/cron/
    label: "decree: clean-runs.md (prune old run logs weekly)"
    requires: EXIST_IS_SERVICES_DECREE
  - src: services/decree/decree/cron.example/health-checks.md
    dst: services/decree/decree/cron/
    label: "decree: health-checks.md"
    requires: EXIST_IS_SERVICES_DECREE
---

Core is the whole system in one pass: your files, your house, a local agent
that reads both, and a voice to talk to it. Everything below runs on your
hardware — no API keys, no accounts, nothing leaving the box.

What you get:
  Nextcloud + MinIO      files, with the bucket mounted into Nextcloud as /S3,
                         and the S3 events that let Decree react to them
  Home Assistant         the house, plus voice via wyoming-whisper/piper
  Ollama                 the local models everything else talks to
  Hermes                 the agent — the thing you actually converse with
  Open WebUI             the chat window onto Hermes, in your browser
  Honcho + OpenViking    what it remembers, and what it can look things up in
  Firecrawl              turns a URL into clean text the agent can read
  Decree                 runs it all on a schedule, headless
  Caddy                  https://<service>.<domain> for every one of them
  Dashy                  one page linking to all of the above

── Sizing ──────────────────────────────────────────────────────────────────

Roughly 27 containers. The models are sized to the VRAM you picked at the
start: one multimodal model handles chat, background memory work and images,
with bge-m3 alongside it for embeddings. Speech-to-text and text-to-speech
run on CPU so they never evict the LLM mid-answer.

Re-size any time with `./existential.sh run models`, or edit the "Model
Selection" block in .env.shared directly:

    EXIST_MODEL_CHAT          the agent's brain — MUST support tool calling
    EXIST_MODEL_CHAT_NUM_CTX  its context window — 64k on every tier, because
                              hermes needs it
    EXIST_MODEL_EXTRACT       background memory work — same tag as chat
    EXIST_MODEL_VISION        OCR and image chat — same tag as chat
    EXIST_MODEL_EMBED         embeddings — do NOT change after first ingestion
    EXIST_MODEL_STT           Home Assistant speech to text (CPU)
    EXIST_MODEL_TTS_VOICE     Home Assistant voice (CPU)

Honcho's config and OpenViking's embedding settings are rendered from those,
so the whole stack can never disagree about which model it is using.

── After `docker compose up -d` ────────────────────────────────────────────

Almost nothing. ./existential.sh already seeded hermes' config before the
container starts, so the agent comes up pointed at ollama, with honcho memory
on and the OpenViking + Firecrawl MCP servers registered. Models pull
themselves: the ollama-decree migrations you just copied run as soon as ollama
is healthy (~5.5 GB at the 8 GB default, a few minutes).

  Watch the pulls:  docker logs -f ollama-decree
  Check everything: ./existential.sh test services

Then open https://dashy.<domain> — that is your landing page, with a link and a
live status dot for every core service. ./existential.sh prints the URL when it
finishes.

Two things genuinely need you, because they happen inside another app's UI:

1. Home Assistant voice. Open https://homeassistant.<domain>, finish the
   onboarding wizard, then add TWO Wyoming integrations:
     Settings → Devices & Services → Add Integration → Wyoming Protocol
       host: wyoming-whisper   port: 10300     (speech to text)
       host: wyoming-piper     port: 10200     (text to speech)
   Then Settings → Voice assistants → create a pipeline using those two, and
   set the conversation agent to Ollama (http://ollama:11434).

2. Nextcloud's admin credentials were generated for you — they are in
   nas/nextcloud/.env as NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD. It
   installs itself and lands on a login page; the MinIO bucket is already
   mounted as an "S3" folder in Files. Open WebUI's credentials work the same
   way — ai/open-webui/.env, OPEN_WEBUI_ADMIN_EMAIL / OPEN_WEBUI_ADMIN_PASSWORD.

To CHANGE what was seeded (each overwrites; the seeding never does):
  ./existential.sh run hermes setup      # pick a different model/provider
  ./existential.sh run openviking mcp    # re-register an MCP server
  ./existential.sh run models            # re-size for a different GPU
