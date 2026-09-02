#!/usr/bin/env bash
# exist.test.sh — validate that whisperx (WhisperX-FastAPI) is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "whisperx" EXIST_IS_AI_WHISPERX
skip_if_disabled

# WhisperX-FastAPI serves on :8000. /health answers as soon as gunicorn is up and
# proves nothing about the service working — models load lazily per request, so a
# whisperx with an unwritable DB volume or no HF token answers it happily.
# /health/ready additionally checks the SQLite connection, and GET /speakers is a
# real read of the speaker-embedding table through the ORM (read-only, and empty
# until diarization has stored one).
probe_service "whisperx /health/ready" whisperx 8000 /health/ready 200
probe_service "whisperx /speakers"     whisperx 8000 /speakers     200

# Transcription itself cannot be exercised read-only — a real request downloads
# large-v3 and runs it. The one thing that IS checkable ahead of time is the token,
# because without it the transcribe and align steps succeed and only the diarize
# step 401s: the task fails, every health route stays green, and the whole point
# of running whisperx over wyoming-whisper (speaker labels) is silently gone.
env_var_set "whisperx HF token" WHISPERX_HF_TOKEN

finish
