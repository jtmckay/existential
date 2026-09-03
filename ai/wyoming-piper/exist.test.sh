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
# Wyoming frames each event as a JSON header LINE followed by exactly
# data_length bytes of payload; the voices list lives in that payload. A fixed
# `head -c 4096` blocks forever waiting for bytes the server never sends —
# handle_event() returns after the info reply without closing the connection
# (wyoming_piper/handler.py:120-124), and one voice's info is nowhere near
# 4096 bytes — so timeout killed it and the captured output was empty, failing
# this check on every install while the service was perfectly healthy. Read
# the header line, then exactly the payload it declares.
RESP=$(timeout 10 bash -c '
    exec 3<>/dev/tcp/wyoming-piper/10200 || exit 1
    printf "{\"type\": \"describe\"}\n" >&3
    IFS= read -r header <&3 || exit 1
    printf "%s\n" "$header"
    len=$(printf "%s" "$header" | sed -n "s/.*\"data_length\"[[:space:]]*:[[:space:]]*\\([0-9]*\\).*/\\1/p")
    [ -n "$len" ] && [ "$len" -gt 0 ] && head -c "$len" <&3
' 2>/dev/null || true)

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
