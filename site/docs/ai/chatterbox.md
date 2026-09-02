---
sidebar_position: 4
---

# Chatterbox

- Source: https://github.com/resemble-ai/chatterbox (model)
- Server: https://github.com/devnen/Chatterbox-TTS-Server (the image this runs)
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

:::caution Generated audio is watermarked
Chatterbox stamps every waveform it produces with Resemble AI's
[Perth](https://github.com/resemble-ai/perth) imperceptible watermark, in the
model package itself (`chatterbox/tts.py` applies `PerthImplicitWatermarker` on
every synthesis). There is no setting to turn it off.
:::
