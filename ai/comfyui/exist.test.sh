#!/usr/bin/env bash
# exist.test.sh — validate that comfyui is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.
# Run via: ./existential.sh run comfyui test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "comfyui" EXIST_IS_AI_COMFYUI
skip_if_disabled

# ComfyUI listens on :8188 inside the container.
probe_service "comfyui /"            comfyui 8188 /            200
probe_service "comfyui /system_stats" comfyui 8188 /system_stats 200

finish
