---
sidebar_position: 3
---

# WhisperX

- Source: https://github.com/m-bain/whisperX
- Server: [whisperX-FastAPI](https://github.com/pavelzbornik/whisperX-FastAPI)
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: faster-whisper / Speaches, Parakeet, Vosk, Wav2Vec2

Speech-to-text transcription with **speaker diarization** (who said what),
served by whisperX-FastAPI on an OpenAI-compatible API.

:::note Not the Home Assistant one
This is for **long recordings** — an interview, a meeting, a voice memo — where
you want to know who said what. It runs on the GPU and is driven by decree.

Home Assistant's voice pipeline uses [wyoming-whisper](./wyoming-whisper)
instead: HA speaks the Wyoming TCP protocol, not HTTP, and short voice commands
want low latency far more than they want speaker labels.
:::

## Setup

Diarization needs a HuggingFace token (`WHISPERX_HF_TOKEN`, prompted during setup).
Accept the gated model terms once while logged in:

- https://huggingface.co/pyannote/speaker-diarization-community-1

Without the token, transcription and alignment still succeed and the task then
fails at the diarize step with a HuggingFace 401 — every health route stays green,
so check the task's `error` field, not the service.

## References

- [whisperX-FastAPI](https://github.com/pavelzbornik/whisperX-FastAPI) — the server wrapper
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) — the diarization models
- [Recording Transcription](../flows/recording-transcription) — the automated, diarized pipeline
