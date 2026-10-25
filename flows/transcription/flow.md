---
name: Voice memos you actually read
tagline: A recording synced to Nextcloud gets a speaker-labelled transcript beside it
docs: /docs/flows/recording-transcription
services:
  - EXIST_IS_AI_WHISPERX
flows:
  - nextcloud-capture
processors:
  - whisperx-transcribe.sh
---

Speaker labels need a HuggingFace token: accept the model terms at
https://huggingface.co/pyannote/speaker-diarization-community-1, and WhisperX's setup
asks for the token (WHISPERX_HF_TOKEN).
