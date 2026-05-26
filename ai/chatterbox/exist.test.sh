#!/usr/bin/env bash
# exist.test.sh — validate that chatterbox is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.
# Run via: ./existential.sh setup chatterbox test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "chatterbox" EXIST_IS_AI_CHATTERBOX
skip_if_disabled

# chatterbox-tts-server listens on :8000 inside the container.
probe_service_any "chatterbox root"    chatterbox 8000 /     "^(200|404|307|308)$"
probe_service     "chatterbox /docs"   chatterbox 8000 /docs 200

finish
