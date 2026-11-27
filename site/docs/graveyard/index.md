---
sidebar_position: 1
---

# Alternatives

What was tried, or looked at, and why it isn't here. A tool that leaves the stack gets a row
here; its old page is in git history.

| Tool | What it is | Why not |
|---|---|---|
| **AI** | | |
| [AionUI](https://github.com/AionUI/aion-ui) | AI chat interface | No way to configure it but its UI, so no reproducible setup |
| [Flowise](https://github.com/FlowiseAI/Flowise) | Visual builder for LLM pipelines | Not evaluated; decree plugins cover it |
| [Hermes](https://github.com/NousResearch/hermes-agent) | Agent gateway with an OpenAI-compatible API | Replaced by [pi](../ai/pi.md) in 2026-10: a 1 GB container, a ~17k-token prompt per call, a config to keep reconciled |
| [Honcho](https://github.com/plastic-labs/honcho) | Cross-session memory in Postgres | Retired with Hermes, its only consumer |
| [LibreChat](https://github.com/danny-avila/LibreChat) | Multi-provider chat UI | Retired; [Open WebUI](../ai/open-web-ui.md) is the chat front end |
| [LightRAG](https://github.com/HKUDS/LightRAG) | GraphRAG over a vault | Replaced by OpenViking, then by [qmd](../ai/qmd.md) |
| [LocalAI](https://github.com/mudler/LocalAI) | OpenAI-compatible local model server | Broke on an AMD Linux host; no gain over Ollama |
| [Open Notebook](https://github.com/lfnovo/open-notebook) | Self-hosted NotebookLM | Not evaluated |
| [OpenViking](https://github.com/volcengine/OpenViking) | Context database for agents | Replaced by [qmd](../ai/qmd.md) in 2026-11: CPU only, no embedding model, fresher |
| [Parakeet](https://github.com/NVIDIA/NeMo) | NVIDIA's GPU speech-to-text | Not evaluated; [WhisperX](../ai/whisperx.md) does it with speaker labels |
| [Speaches](https://github.com/speaches-ai/speaches) | OpenAI-compatible text-to-speech | Not evaluated; [Chatterbox](../ai/chatterbox.md) fills the slot |
| [vLLM](https://github.com/vllm-project/vllm) | High-throughput model server | Needs more VRAM than a home card has |
| **Automation** | | |
| [ActivePieces](https://github.com/activepieces/activepieces) | Visual workflow builder | Closed-source licensing practices |
| [Kestra](https://github.com/kestra-io/kestra) | YAML pipelines | Not evaluated; decree does it |
| [n8n](https://github.com/n8n-io/n8n) | Visual workflow builder | Sustainable Use License: can't automate anything for anyone else |
| [Node-RED](https://github.com/node-red/node-red) | Flow-based wiring | Built for IoT, not general automation |
| [Windmill](https://github.com/windmill-labs/windmill) | Scripts and workflows | Replaced by decree: sharing scripts is behind an enterprise license |
| **Files and documents** | | |
| [MinIO](https://github.com/minio/minio) | S3 object store | Web console stripped from the community edition in 2025; archived upstream in 2026 |
| [SeaweedFS](https://github.com/seaweedfs/seaweedfs) | Object store | Only there for file events, at the cost of a second copy of everything; Nextcloud does it alone |
| [OnlyOffice](https://github.com/ONLYOFFICE/DocumentServer) | Office suite for Nextcloud | Retired; [Collabora](../storage/collabora.md) fills the slot |
| [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF) | PDF toolkit | Only needed for text fields, which the office suite does |
| **Notes and tasks** | | |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) | Notion-like editor | Never got a login working against its database |
| [Logseq](https://github.com/logseq/logseq) | Outliner over markdown | Replaced by [Obsidian](../services/obsidian.md), reading the same files |
| [Nightlio](https://github.com/shirsakm/nightlio) | Daily check-in journal | Its Docker images were broken |
| [Standard Notes](https://github.com/standardnotes/server) | Encrypted notes | Sync issues; no links between notes |
| [Trilium](https://github.com/TriliumNext/Notes) | Hierarchical notes | Poor markdown support |
| [Super Productivity](https://github.com/johannesjo/super-productivity) | Tasks and time tracking | Sync broke beyond repair after a few weeks |
| [Vikunja](https://github.com/go-vikunja/vikunja) | Task manager | More machinery than the job; tasks are markdown now ([Obsidian Kanban](../services/obsidian.md#kanban)) |
| **Infrastructure** | | |
| [Docker Swarm](https://github.com/moby/moby) | Multi-host orchestration | Networking and env variables got harder, not easier |
| [Fabric](https://github.com/danielmiessler/fabric) | LLM prompt library | The prompts are better kept as searchable notes |
| [Linkwarden](https://github.com/linkwarden/linkwarden) | Bookmark archive | No export, and slow to load hundreds of bookmarks |
| [ngrok](https://github.com/ngrok/ngrok) | Tunnels to the internet | Unneeded with a VPN or Tailscale |
| [NSQ](https://github.com/nsqio/nsq) | Distributed queue | Replaced by RabbitMQ, then by ntfy and webhooks |
| [RabbitMQ](https://github.com/rabbitmq/rabbitmq-server) | Message broker | Replaced by [ntfy](../services/ntfy.md) and direct webhooks |
