---
service: ai/open-webui
sidebar_position: 5
---

# Open WebUI

- Source: https://github.com/open-webui/open-webui
- License: BSD-3-Clause-derived (branding restrictions apply)
- Alternatives: LibreChat
- UI: `https://open-webui.<domain>`

Chat interface for LLMs, talking straight to the stack's chat model and to [WhisperX](./whisperx)
for speech-to-text.

## Enable

Not part of Core. The chat model already answers by voice (Home Assistant), from code-server's
terminal (`pi`, `opencode`), and from decree routines. Turn this on when you want a chat window in
a browser tab:

```bash
EXIST_IS_AI_OPEN_WEBUI=true
```

Then `./existential.sh && docker compose up -d` from the repo root. Admin credentials are
generated into `ai/open-webui/.env` (`OPEN_WEBUI_ADMIN_EMAIL` / `OPEN_WEBUI_ADMIN_PASSWORD`).

## Recommended Workflow

| Tool | Use for |
|---|---|
| Open WebUI | Day-to-day conversations |
| `pi` in [code-server](../services/code-server)'s terminal | The same model with tools: the workspace, search and the web |
| [decree](../decree/) routines | Work with nobody present — `agent_task` files the answer into `workspace/ai/` |

## Backend Wiring

| Container env var | Value |
|---|---|
| `OPENAI_API_BASE_URLS` | the chat role's endpoint, `EXIST_MODEL_URL_CHAT` (else `EXIST_MODEL_URL`), resolved at render |
| `OPENAI_API_KEYS` | `none` — the model server takes no key |
| `AUDIO_STT_OPENAI_API_BASE_URL` | `http://whisperx:8000/v1` |

A rendered file is never re-rendered, so moving the chat role later means editing
`ai/open-webui/docker-compose.yml` too (or `./existential.sh reset`).

## Admin Account

Set on first boot via `ai/open-webui/.env`:

```
OPEN_WEBUI_ADMIN_NAME
OPEN_WEBUI_ADMIN_EMAIL
OPEN_WEBUI_ADMIN_PASSWORD
```

These default to `EXIST_USERNAME` / `EXIST_EMAIL` / `EXIST_PASSWORD` from the root `.env.shared`.

## Debugging

```bash
docker compose logs open-webui
```
