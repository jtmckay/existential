#!/usr/bin/env bash
# exist.test.sh — validate that chatterbox is fully operational.
#
# Read-only: /api/model-info and /v1/audio/voices are GETs, and the synthesis
# probe writes nothing server-side (audio_output.save_to_disk is false, and the
# OpenAI route only touches outputs/ when it is true).
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run chatterbox test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "chatterbox" EXIST_IS_AI_CHATTERBOX
skip_if_disabled

# config.yaml pins server.port to 8000 (upstream's own default is 8004).
URL="http://chatterbox:8000"

# ── 1. Routing ────────────────────────────────────────────────────────────────
#
# /api/model-info, not / or /docs. The model is loaded in the FastAPI lifespan
# and a failure there is only logged — the server still binds and answers 200 on
# both / and /docs with no model loaded at all, so the old reachability probe
# passed a completely inert service. Verified against the 2.0.0 image with an
# empty HF cache: / -> 200, /docs -> 200, /api/model-info -> {"loaded":false,...}.
probe_service "chatterbox /api/model-info" chatterbox 8000 /api/model-info 200

# ── 2. Model actually loaded ─────────────────────────────────────────────────

INFO=$(curl -sS --max-time 10 "${URL}/api/model-info" 2>/dev/null || true)
if [ -z "$INFO" ]; then
    fail "model info readable" "no response from ${URL}/api/model-info within 10s" \
         "docker ps | grep chatterbox; docker logs chatterbox"
    finish
fi

read -r LOADED MTYPE DEVICE <<INFO_EOF
$(echo "$INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(str(d.get('loaded')).lower(), d.get('type') or 'none', d.get('device') or 'none')
except Exception:
    print('false none none')
" 2>/dev/null || echo "false none none")
INFO_EOF

if [ "${LOADED:-false}" != "true" ]; then
    fail "TTS model loaded" \
         "/api/model-info reports loaded=false — the server answers but every synthesis returns 503" \
         "First boot pulls ~3.2GB from HuggingFace into volumes/chatterbox_cache; check: docker logs chatterbox | grep -i 'failed to load'"
    finish
fi
ok "TTS model loaded: ${MTYPE} on ${DEVICE}"

# ── 3. A voice to synthesize with ────────────────────────────────────────────
#
# /v1/audio/speech resolves `voice` as a filename under voices/ then
# reference_audio/ and 404s if neither has it — an unmounted voices/ is a
# silently broken install that everything else still reports as healthy.
VOICE=$(curl -sS --max-time 10 "${URL}/v1/audio/voices" 2>/dev/null | python3 -c "
import sys, json
try:
    print((json.load(sys.stdin).get('voices') or [''])[0])
except Exception:
    print('')
" 2>/dev/null || echo "")
if [ -z "$VOICE" ]; then
    fail "predefined voices present" \
         "/v1/audio/voices returned none — ai/chatterbox/voices is empty or not mounted" \
         "ls ai/chatterbox/voices; docker inspect chatterbox --format '{{json .Mounts}}'"
    finish
fi
ok "predefined voices available (using ${VOICE})"

# ── 4. Real synthesis ────────────────────────────────────────────────────────
#
# The point of the whole service. `model` is a required field on this route
# (its value is ignored) — omitting it is a 422, not a default. CPU inference is
# slow, hence the 180s ceiling.
WAV=$(mktemp)
trap 'rm -f "$WAV"' EXIT
CODE=$(curl -sS --max-time 180 -o "$WAV" -w '%{http_code}' \
    -X POST "${URL}/v1/audio/speech" -H 'Content-Type: application/json' \
    -d "{\"model\":\"chatterbox\",\"input\":\"Existential check.\",\"voice\":\"${VOICE}\",\"response_format\":\"wav\"}" \
    2>/dev/null || echo 000)

if [ "$CODE" != "200" ]; then
    fail "synthesis returns audio" \
         "HTTP ${CODE} from /v1/audio/speech: $(head -c 200 "$WAV")" \
         "docker logs chatterbox"
elif [ "$(head -c 4 "$WAV")" != "RIFF" ]; then
    fail "synthesis returns audio" \
         "200 but the body is not a WAV (first bytes: $(head -c 16 "$WAV" | od -An -c | tr -s ' '))" \
         "docker logs chatterbox"
else
    BYTES=$(wc -c < "$WAV")
    if [ "$BYTES" -lt 8000 ]; then
        fail "synthesis returns audio" \
             "WAV is only ${BYTES} bytes — near-silent output" \
             "docker logs chatterbox"
    else
        ok "synthesis returned a ${BYTES}-byte WAV"
    fi
fi

finish
