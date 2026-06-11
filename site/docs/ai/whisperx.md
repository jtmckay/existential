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

## Features

- **High-Accuracy Transcription**: WhisperX wraps faster-whisper; runs `large-v3`
  in `int8` on the GPU
- **Speaker Diarization**: pyannote labels each segment with a speaker
  (`SPEAKER_00`, `SPEAKER_01`, …) — requires a HuggingFace token
- **Word-Level Alignment**: forced alignment for accurate per-word timestamps
- **Persistent Speakers**: optional speaker-embedding database to recognise
  recurring voices across recordings
- **Dual API**: native async endpoints (`/speech-to-text`, `/speech-to-text-url`,
  `/service/diarize`) plus OpenAI-compatible `/v1/audio/transcriptions` for tools
  like open-webui

## Setup

Diarization needs a HuggingFace token (`WHISPERX_HF_TOKEN`, prompted during setup).
Accept the gated model terms once while logged in:

- https://huggingface.co/pyannote/speaker-diarization-3.1
- https://huggingface.co/pyannote/segmentation-3.0

Without the token, plain transcription still works but diarization fails.

## References

- [whisperX-FastAPI](https://github.com/pavelzbornik/whisperX-FastAPI) — the server wrapper
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) — the diarization models
- [Recording Transcription](../decree/recording-transcription) — the automated, diarized pipeline
