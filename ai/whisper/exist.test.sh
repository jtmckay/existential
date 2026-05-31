#!/usr/bin/env bash
# exist.test.sh — validate that whisper (faster-whisper-server) is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "whisper" EXIST_IS_AI_WHISPER
skip_if_disabled

# faster-whisper-server exposes an OpenAI-compatible API on :8000.
probe_service "whisper /health"    whisper 8000 /health    200
probe_service "whisper /v1/models" whisper 8000 /v1/models 200

finish
