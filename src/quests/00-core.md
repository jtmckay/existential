---
name: Core
tagline: The whole system, wired together — files, house, agent, memory, voice
e2e: true
# Core is only meaningful with a chat model behind it, and a CI runner has no
# GPU — so e2e runs ollama on the CPU against the 1B model pinned in
# src/test/fixtures/env.shared. That is slow per token but fast to pull, and it
# means the flagship path is exercised on every run rather than only when
# someone has a second box to point at.
services:
  - var: EXIST_IS_HOSTING_CADDY
    label: Caddy (TLS + hostnames)
  - var: EXIST_IS_SERVICES_DASHY
    label: Dashy (the dashboard — links to everything below)
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files)
  - var: EXIST_IS_NAS_REDIS
    label: Redis (Nextcloud cache — required by Nextcloud)
  - var: EXIST_IS_NAS_SEAWEEDFS
    label: SeaweedFS (S3 + file events)
  - var: EXIST_IS_SERVICES_HOMEASSISTANT
    label: Home Assistant (the house)
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (automation engine)
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy (push notifications — where automations report in)
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki (log store — Decree's run logs land here)
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus (metrics store)
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana (the window onto both — ships Decree dashboards)
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
  - src: automation-examples/migrations/10-ollama-pull-chat-model.md
    dst: automation/migrations/
    label: "ollama: pull the chat model (EXIST_MODEL_CHAT)"
    requires: EXIST_IS_AI_OLLAMA
  - src: automation-examples/migrations/11-ollama-set-chat-context.md
    dst: automation/migrations/
    label: "ollama: apply the chat context window (EXIST_MODEL_CHAT_NUM_CTX)"
    requires: EXIST_IS_AI_OLLAMA
  - src: automation-examples/migrations/12-ollama-pull-extract-model.md
    dst: automation/migrations/
    label: "ollama: pull the extraction model (EXIST_MODEL_EXTRACT)"
    requires: EXIST_IS_AI_OLLAMA
  - src: automation-examples/migrations/13-ollama-pull-embed-model.md
    dst: automation/migrations/
    label: "ollama: pull the embedding model (EXIST_MODEL_EMBED)"
    requires: EXIST_IS_AI_OLLAMA
  - src: automation-examples/migrations/14-ollama-pull-vision-model.md
    dst: automation/migrations/
    label: "ollama: pull the vision model (skips when EXIST_MODEL_VISION is blank)"
    requires: EXIST_IS_AI_OLLAMA
  # Bidirectional workspace/ <-> the nextcloud bucket's workspace/ subfolder.
  # seaweedfs pre-creates that bucket itself (-bucket flag), so unlike the ollama
  # rows above there is no migration to copy first.
  - src: services/automation/backup/cron.example/workspace-sync.md
    dst: services/automation/backup/cron/
    label: "decree: workspace-sync.md (bisync workspace/ with seaweedfs every 10m)"
    requires: EXIST_IS_NAS_SEAWEEDFS
  # file-processor's download step for anything reached through Nextcloud's
  # WebDAV (rclone_src: nextcloud) — including workspace-pull below. Without
  # it every such download fails with "didn't find section in config file".
  - src: automation-examples/migrations/23-nextcloud-rclone-remote.md
    dst: automation/migrations/
    label: "nextcloud: configure the rclone remote (WebDAV, admin creds)"
    requires: EXIST_IS_NAS_SEAWEEDFS
  # Without this, https://homeassistant.<domain> redirects every page to the
  # setup wizard until a human creates an admin account by hand.
  - src: automation-examples/migrations/25-homeassistant-onboarding.md
    dst: automation/migrations/
    label: "homeassistant: create the admin account (EXIST_USERNAME login)"
    requires: EXIST_IS_SERVICES_HOMEASSISTANT
  # Wyoming STT/TTS + a conversation-agent entry pointed at Hermes (not raw
  # OpenAI — see exist.initial.sh's extended_openai_conversation install) +
  # the Assist pipeline tying them together. Needs the migration above to
  # have created an account first.
  - src: automation-examples/migrations/26-homeassistant-wyoming-hermes.md
    dst: automation/migrations/
    label: "homeassistant: wire up Wyoming STT/TTS + Hermes as the Assist pipeline"
    requires: EXIST_IS_SERVICES_HOMEASSISTANT
  # The live half of workspace-sync's bucket -> local direction: a bucket-side
  # edit reaches workspace/ in ~1s via the webhook instead of waiting for the
  # cron. s3-router/file-processor are already on by default in
  # services/automation/decree/config.exist.yml — nothing else to enable.
  - src: automation/lib/file-processors.example/workspace-pull.sh
    dst: automation/lib/file-processors/
    label: "decree: workspace-pull.sh (live bucket -> workspace/ file processor)"
    requires: EXIST_IS_NAS_SEAWEEDFS
  # The one door from workspace/ into decree's inbox: an agent confined to
  # workspace/ (hermes, OpenCode) drops a message in workspace/outbox/ instead
  # of ever touching automation/ directly. Same live path as workspace-pull.
  - src: automation/lib/file-processors.example/outbox-relay.sh
    dst: automation/lib/file-processors/
    label: "decree: outbox-relay.sh (workspace/outbox/ -> decree inbox)"
    requires: EXIST_IS_NAS_SEAWEEDFS
  - src: automation-examples/cron/clean-runs.md
    dst: automation/cron/
    label: "decree: clean-runs.md (prune old run logs weekly)"
    requires: EXIST_IS_SERVICES_AUTOMATION
  - src: automation-examples/cron/health-checks.md
    dst: automation/cron/
    label: "decree: health-checks.md"
    requires: EXIST_IS_SERVICES_AUTOMATION
  # Keeps workspace/ searchable. Core installs openviking as the agent's context
  # database, but nothing puts anything IN it — without this cron hermes answers
  # from the model alone and the "it knows your material" half of Core is inert.
  # Same tree hermes and code-server already share, so there is nothing to place.
  - src: automation-examples/cron/openviking-index-knowledgebase.md
    dst: automation/cron/
    label: "decree: openviking-index-knowledgebase.md (index workspace/ every 15m)"
    requires: EXIST_IS_AI_OPENVIKING
  # Needs the same index the entry above builds, so it rides the same requires.
  # note-connect.sh defaults NOTES_DIR to /workspace, so this needs nothing
  # else Core doesn't already provide. To opt out later, delete
  # automation/cron/note-connect.md — enabled: true in config.yml with no
  # cron file behind it never fires.
  - src: automation-examples/cron/note-connect.md
    dst: automation/cron/
    label: "decree: note-connect.md (surface connections to what you already know, hourly)"
    requires: EXIST_IS_AI_OPENVIKING
---

Core is the whole system in one pass: your files, your house, a local agent
that reads both, and a voice to talk to it. Everything below runs on your
hardware — no API keys, no accounts, nothing leaving the box.

What you get:
  Nextcloud + SeaweedFS  files, with the bucket mounted into Nextcloud as /S3,
                         and the S3 events that let Decree react to them
  Home Assistant         the house, plus voice via wyoming-whisper/piper
  Ollama                 the local models everything else talks to
  Hermes                 the agent — the thing you actually converse with
  Open WebUI             the chat window onto Hermes, in your browser
  Honcho + OpenViking    what it remembers, and what it can look things up in
  Firecrawl              turns a URL into clean text the agent can read
  Decree                 runs it all on a schedule, headless
  ntfy                   how a finished automation tells you it finished
  Loki + Grafana         every Decree run log, searchable, with two dashboards
                         wired up before you get there
  Prometheus             the metrics behind those dashboards
  Caddy                  https://<service>.<domain> for every one of them
  Dashy                  one page linking to all of the above

── Sizing ──────────────────────────────────────────────────────────────────

Roughly 34 containers. The observability half is seven of them and costs about
1 GB in practice; every one carries a memory limit, so a runaway query cannot
take the box down with it. The models are sized to the VRAM you picked at the
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
themselves: the ollama migrations you just copied run in the decree daemon as
soon as ollama is healthy (~5.5 GB at the 8 GB default, a few minutes).

  Watch the pulls:  docker logs -f automation
  Check everything: ./existential.sh test services

Grafana comes up with the Loki and Prometheus datasources already wired and two
Decree dashboards already loaded — an overview and a per-run detail view. When a
routine misbehaves, that is where you look, rather than in `docker logs automation`:
alloy labels every run log with its message_id, chain and seq, so a routed
chain reads end to end. Grafana's credentials are generated for you, in
hosting/grafana/.env.

ntfy provisions itself the same way: its entrypoint creates your admin login
(services/ntfy/.env) and the exist-bot publisher (EXIST_NTFY_USER /
EXIST_NTFY_PASSWORD in .env.shared) on first boot, and Decree publishes as the
bot. Point the ntfy mobile app at https://ntfy.<domain>, log in as the admin,
and subscribe to the "decree" topic. `./existential.sh run ntfy setup` is only
needed if you would rather use a bearer token than the generated password.

Then open https://dashy.<domain> — that is your landing page, with a link and a
live status dot for every core service. ./existential.sh prints the URL when it
finishes.

One thing genuinely needs you, because it happens inside another app's UI:

1. Nextcloud's admin credentials were generated for you — they are in
   nas/nextcloud/.env as NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD. It
   installs itself and lands on a login page; the seaweedfs bucket is already
   mounted as an "S3" folder in Files. Open WebUI's credentials work the same
   way — ai/open-webui/.env, OPEN_WEBUI_ADMIN_EMAIL / OPEN_WEBUI_ADMIN_PASSWORD.

To CHANGE what was seeded (each overwrites; the seeding never does):
  ./existential.sh run hermes setup      # pick a different model/provider
  ./existential.sh run openviking mcp    # re-register an MCP server
  ./existential.sh run models            # re-size for a different GPU
