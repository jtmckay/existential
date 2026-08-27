#!/usr/bin/env bash
# exist.test.sh — validate that wyoming-whisper (STT for Home Assistant) is operational.
#
# Read-only: `describe` is the Wyoming protocol's capability handshake and
# transcribes nothing, so it changes no state.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "wyoming-whisper" EXIST_IS_AI_WYOMING_WHISPER
skip_if_disabled

# Wyoming is raw TCP — there is no HTTP surface to probe, so no probe_service here.
# First start downloads the model before the socket opens; the compose
# healthcheck allows 180s for that, and this probe is generous for the same reason.
tcp_probe "wyoming-whisper:10300" wyoming-whisper 10300 10

# Wyoming handshake: a `describe` event returns an `info` event listing the
# loaded ASR models. This is what Home Assistant issues when you add the
# integration, so a pass here means HA will see the service too.
RESP=$(printf '{"type": "describe"}\n' \
        | timeout 15 bash -c 'cat >&3; head -c 4096 <&3' 3<>/dev/tcp/wyoming-whisper/10300 2>/dev/null || true)

if printf '%s' "$RESP" | grep -q '"type"[[:space:]]*:[[:space:]]*"info"'; then
    ok "wyoming-whisper describe"
else
    fail "wyoming-whisper describe" \
         "no info event (got $(printf '%s' "$RESP" | head -c 80))" \
         "Model download may still be running on first start: docker logs wyoming-whisper"
fi

# A server that answers `describe` with an empty asr list has no model — HA
# then shows the integration with nothing to select.
if printf '%s' "$RESP" | grep -q '"asr"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'; then
    warn "wyoming-whisper model loaded" \
         "info event lists no ASR models" \
         "Check EXIST_MODEL_STT in .env.shared names a real faster-whisper size (tiny|base|small|medium|large-v3), then: docker compose restart wyoming-whisper"
else
    ok "wyoming-whisper model loaded"
fi

finish
