---
sidebar_position: 4
---

# Chatterbox

- Source: https://github.com/resemble-ai/chatterbox
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Speaches, Piper, Coqui TTS, ElevenLabs

Text-to-speech (TTS) service for generating audio from text, over an
OpenAI-compatible HTTP API.

:::note Not the Home Assistant one
Home Assistant's voice pipeline uses [wyoming-piper](./wyoming-piper) instead:
HA speaks the Wyoming TCP protocol, not HTTP, so it cannot drive Chatterbox
without a bridge.

Reach for Chatterbox when something in the stack is generating audio over HTTP
and you want an expressive or cloned voice.
:::

