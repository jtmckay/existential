#!/usr/bin/env bash
# exist.test.sh — validate that wyoming-piper (TTS for Home Assistant) is operational.
#
# Read-only: `describe` is the Wyoming protocol's capability handshake and
# synthesises nothing, so it changes no state and writes no audio.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "wyoming-piper" EXIST_IS_AI_WYOMING_PIPER
skip_if_disabled

# Wyoming is raw TCP — there is no HTTP surface to probe, so no probe_service here.
tcp_probe "wyoming-piper:10200" wyoming-piper 10200

# Wyoming handshake: a `describe` event returns an `info` event listing the
# loaded voices. This is what Home Assistant issues when you add the
# integration, so a pass here means HA will see the service too.
#
# Wire format is a JSON header line, then optional data/payload bytes. We only
# need the header of the reply.
RESP=$(printf '{"type": "describe"}\n' \
        | timeout 10 bash -c 'cat >&3; head -c 4096 <&3' 3<>/dev/tcp/wyoming-piper/10200 2>/dev/null || true)

if printf '%s' "$RESP" | grep -q '"type"[[:space:]]*:[[:space:]]*"info"'; then
    ok "wyoming-piper describe"
else
    fail "wyoming-piper describe" \
         "no info event (got $(printf '%s' "$RESP" | head -c 80))" \
         "Voice download may still be running on first start: docker logs wyoming-piper"
fi

# A piper server with no voice loaded still answers `describe`, but announces an
# empty voice list — HA then shows the integration with nothing to select.
if printf '%s' "$RESP" | grep -q '"voices"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'; then
    warn "wyoming-piper voice loaded" \
         "info event lists no voices" \
         "Check EXIST_MODEL_TTS_VOICE in .env.shared names a real piper voice (https://rhasspy.github.io/piper-samples/), then: docker compose restart wyoming-piper"
else
    ok "wyoming-piper voice loaded"
fi

finish
