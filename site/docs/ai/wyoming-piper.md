---
sidebar_position: 8
---

# wyoming-piper

- Source: https://github.com/OHF-Voice/wyoming-piper
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: [Chatterbox](./chatterbox) (expressive TTS over HTTP), Coqui TTS

Text-to-speech for Home Assistant's Assist pipeline. Runs on CPU.

## Why this and not Chatterbox

Home Assistant's Assist pipeline speaks the **Wyoming protocol** — a small,
line-oriented TCP protocol — not HTTP. Chatterbox is an OpenAI-compatible HTTP
server, so HA cannot drive it without a bridge.

Chatterbox is the better voice when you want expressive, cloned, or
long-form audio and something in the stack is calling it over HTTP. Piper is
what HA's own voice stack expects, and it synthesises faster than real time on
a couple of CPU cores — which is what a spoken reply actually needs.

Running it on CPU is deliberate: the GPU is already holding the chat model and
the embedding model, and the whole point of a voice reply is that it lands
immediately.

## Configuration

The voice is global — set it once in `.env.shared`:

| Variable | Default | Notes |
|---|---|---|
| `EXIST_MODEL_TTS_VOICE` | `en_US-lessac-medium` | `<lang>_<REGION>-<name>-<quality>` |

Browse and listen to the options at
[rhasspy.github.io/piper-samples](https://rhasspy.github.io/piper-samples/).
`medium` is the quality/latency sweet spot on CPU; `low` is faster and
noticeably more robotic; `high` is slower than real time on modest hardware.

## Connecting it to Home Assistant

There is no web UI and no `<slug>.<domain>` hostname — Wyoming is raw TCP, so
there is nothing for Caddy to front. You add it inside Home Assistant:

**Settings → Devices & Services → Add Integration → Wyoming Protocol**

| Field | Value |
|---|---|
| Host | `wyoming-piper` |
| Port | `10200` |

Then build a pipeline under **Settings → Voice assistants**, pairing it with
[wyoming-whisper](./wyoming-whisper) for the listening half.

## Verify

```bash
./existential.sh run wyoming-piper test
```

The first start downloads the voice before the socket opens. If the test warns
that no voice is loaded, check that `EXIST_MODEL_TTS_VOICE` names a real piper
voice and restart the container.
