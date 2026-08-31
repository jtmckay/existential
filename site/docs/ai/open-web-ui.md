---
sidebar_position: 5
---

# Open WebUI

- Source: https://github.com/open-webui/open-webui
- License: BSD-3-Clause-derived (branding restrictions apply)
- Alternatives: LibreChat
- UI: `https://open-webui.<domain>`

Chat interface for LLMs, backed by [Hermes](./hermes) as the OpenAI-compatible endpoint and [WhisperX](./whisperx) for speech-to-text.

## Recommended Workflow

Each tool in the stack has a distinct role:

| Tool | Use for |
|---|---|
| [Hermes dashboard](./hermes) | Managing sessions, skills, and agent configuration |
| Open WebUI | Day-to-day conversations |
| opencode | Coding assistant — connect via Hermes gateway as the OpenAI API endpoint |

Configure opencode to point at the Hermes gateway (`https://hermes-agent.<domain>/v1`) with `HERMES_API_KEY` as the API key so all three surfaces share the same models and skills.

## Backend Wiring

| Variable | Value |
|---|---|
| `OPENAI_API_BASE_URL` | `http://hermes-agent:8642/v1` |
| `OPENAI_API_KEY` | `HERMES_API_KEY` from `ai/hermes/.env.exist` |
| `AUDIO_STT_OPENAI_API_BASE_URL` | `http://whisperx:8000/v1` |

## Admin Account

Set on first boot via `.env`:

```
WEBUI_ADMIN_NAME
WEBUI_ADMIN_EMAIL
WEBUI_ADMIN_PASSWORD
```

These default to `EXIST_*` values from the root `.env.shared`.

## Debugging

```bash
docker compose logs open-webui
```
