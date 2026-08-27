---
sidebar_position: 7
---

# wyoming-whisper

- Source: https://github.com/OHF-Voice/wyoming-faster-whisper
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: [WhisperX](./whisperx) (long recordings), Vosk, Speaches

Speech-to-text for Home Assistant's Assist pipeline. Runs on CPU.

## Why this and not WhisperX

They do different jobs, and only one of them can talk to Home Assistant.

Home Assistant's Assist pipeline speaks the **Wyoming protocol** — a small,
line-oriented TCP protocol — not HTTP. WhisperX is a FastAPI service, so HA
cannot drive it without a bridge.

| | wyoming-whisper | [WhisperX](./whisperx) |
|---|---|---|
| Job | short voice commands | long recordings |
| Speaker labels | no | yes (diarization) |
| Runs on | CPU | GPU |
| Spoken to by | Home Assistant | Decree, via the transcription flow |

Running it on CPU is deliberate. The GPU is already holding the chat model and
the embedding model; a GPU speech model here would evict them every time you
spoke.

## Configuration

Both settings are global — set them once in `.env.shared` and they reach the
container at start:

| Variable | Default | Notes |
|---|---|---|
| `EXIST_MODEL_STT` | `base` | `tiny`, `base`, `small`, `medium`, `large-v3` |
| `EXIST_MODEL_STT_LANGUAGE` | `en` | Pinning beats auto-detect on short commands |

On a few CPU cores, `base` is near-instant and good enough for commands;
`small` is noticeably more accurate and roughly 2–3× the latency; `medium` is
too slow for conversational voice on most homelab hardware.

## Connecting it to Home Assistant

There is no web UI and no `<slug>.<domain>` hostname — Wyoming is raw TCP, so
there is nothing for Caddy to front. You add it inside Home Assistant:

**Settings → Devices & Services → Add Integration → Wyoming Protocol**

| Field | Value |
|---|---|
| Host | `wyoming-whisper` |
| Port | `10300` |

Then build a pipeline under **Settings → Voice assistants**, pairing it with
[wyoming-piper](./wyoming-piper) for the reply.

## Verify

```bash
./existential.sh run wyoming-whisper test
```

The first start downloads the model before the socket opens — allow a couple of
minutes, and watch `docker logs wyoming-whisper` if the test fails immediately.
