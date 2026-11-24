---
name: transcription
x-exist-project: automation
x-exist-title: Voice memos you actually read
x-exist-tagline: A recording synced to Nextcloud gets a speaker-labelled transcript beside it
x-exist-docs: /docs/flows/recording-transcription
x-exist-services:
  - EXIST_IS_AI_WHISPERX
needs:
  - transcribe
  - nextcloud-capture
---

Speaker labels need a HuggingFace token: accept the model terms at
https://huggingface.co/pyannote/speaker-diarization-community-1, and WhisperX's setup
asks for the token (WHISPERX_HF_TOKEN).
