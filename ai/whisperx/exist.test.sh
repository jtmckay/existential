#!/usr/bin/env bash
# exist.test.sh — validate that whisperx (WhisperX-FastAPI) is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "whisperx" EXIST_IS_AI_WHISPERX
skip_if_disabled

# WhisperX-FastAPI serves on :8000. /health is up as soon as the API is live;
# /docs confirms the Swagger surface (which fronts both the diarization endpoints
# and the OpenAI-compatible /v1/audio path open-webui uses for voice input).
probe_service "whisperx /health" whisperx 8000 /health 200
probe_service "whisperx /docs"   whisperx 8000 /docs   200

finish
