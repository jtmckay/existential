#!/usr/bin/env bash
# test-model-gateway.sh — ai/model-gateway/gateway.ts, against a stub fleet lib, a stub GPU
# host and a stub Loki: it keeps out a call without the fleet secret, fronts Loki behind it, lists what the fleet offers,
# sends a call to the host whose offer lists its model under that host's lease (fleet_use,
# then fleet_done once the answer is back), and says so when no host offers the model.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/ai/model-gateway/gateway.ts" ]] || REPO_DIR="/repo"
TSX="$(command -v tsx || echo /opt/decree/node_modules/.bin/tsx)"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()  { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }

TMP="$(mktemp -d)"
PIDS=()
_cleanup() { local p; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap _cleanup EXIT

UP=47811 GW=47812 LK=47813

# The GPU host: answers /v1/chat/completions with the model and key it was sent.
cat > "${TMP}/up.js" <<EOF
require('http').createServer((req, res) => {
  let b = ''; req.on('data', d => b += d).on('end', () => {
    res.writeHead(200, {'content-type': 'application/json'});
    res.end(JSON.stringify({path: req.url, auth: req.headers.authorization, model: JSON.parse(b || '{}').model}));
  });
}).listen(${UP});
EOF
node "${TMP}/up.js" & PIDS+=($!)

# This host's Loki: answers with the path and the key it was sent.
cat > "${TMP}/loki.js" <<EOF
require('http').createServer((req, res) => {
  res.writeHead(200, {'content-type': 'application/json'});
  res.end(JSON.stringify({path: req.url, auth: req.headers.authorization || ''}));
}).listen(${LK});
EOF
node "${TMP}/loki.js" & PIDS+=($!)

# The fleet lib: one host offering llm with two models; fleet_use and fleet_done leave a trace.
cat > "${TMP}/fleet.sh" <<EOF
fleet_offers() { echo '{"host":"gpubox","service":"llm","models":[{"id":"qwen"},{"id":"gemma"}]}'; echo '{"host":"gpubox","service":"comfy"}'; }
fleet_use() { echo "use \$1" >> "${TMP}/trace"; FLEET_URL="http://127.0.0.1:${UP}/v1"; }
fleet_done() { echo "done \$1" >> "${TMP}/trace"; }
EOF

EXIST_FLEET_SECRET=s3cret FLEET_LIB="${TMP}/fleet.sh" FLEET_LOKI_UPSTREAM="http://127.0.0.1:${LK}" PORT=$GW "$TSX" "${REPO_DIR}/ai/model-gateway/gateway.ts" >"${TMP}/gw.log" 2>&1 & PIDS+=($!)
for _ in $(seq 50); do curl -fsS "http://127.0.0.1:${GW}/health" >/dev/null 2>&1 && break; sleep 0.2; done

auth=(-H "Authorization: Bearer s3cret")
assert_eq "it answers /health" '{"ok":true}' "$(curl -fsS "http://127.0.0.1:${GW}/health")"
assert_eq "a call without the fleet secret is refused" "401" \
    "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${GW}/v1/models")"
assert_eq "it lists the models the fleet offers, not comfy" '["qwen","gemma"]' \
    "$(curl -fsS "${auth[@]}" "http://127.0.0.1:${GW}/v1/models" | jq -c '[.data[].id]')"

out="$(curl -fsS "${auth[@]}" -H 'content-type: application/json' -d '{"model":"gemma","messages":[]}' \
    "http://127.0.0.1:${GW}/v1/chat/completions")"
assert_eq "a call reaches the host serving its model, at the same path" "/v1/chat/completions" "$(jq -r .path <<<"$out")"
assert_eq "...with the model it named" "gemma" "$(jq -r .model <<<"$out")"
assert_eq "...and the fleet secret as the host's key" "Bearer s3cret" "$(jq -r .auth <<<"$out")"
sleep 0.5
assert_eq "...under that host's lease, given back once answered" "use llm done llm" "$(xargs < "${TMP}/trace" 2>/dev/null)"

assert_eq "a model no host offers is a 404" "404" \
    "$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" -d '{"model":"nope"}' "http://127.0.0.1:${GW}/v1/chat/completions")"
out="$(curl -fsS "${auth[@]}" -d '{"messages":[]}' "http://127.0.0.1:${GW}/v1/chat/completions")"
assert_eq "no model named: the first one offered answers" "/v1/chat/completions" "$(jq -r .path <<<"$out")"

# fleet_gpu.md: the fleet lib it leases through, as a plugin a decree project of its own installs.
g="$(curl -fsS "${auth[@]}" "http://127.0.0.1:${GW}/plugins/fleet_gpu.md")"
assert_eq "fleet_gpu.md is the fleet lib as a plugin" "name: fleet_gpu" "$(sed -n 2p <<<"$g")"
assert_eq "...with no #! to run" "0" "$(grep -c '#!' <<<"$g")"
assert_eq "...behind the fleet secret" "401" \
    "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${GW}/plugins/fleet_gpu.md")"

# Loki, for the hosts on your own network: behind the secret, which it never passes on.
assert_eq "Loki's push is behind the fleet secret" "401" \
    "$(curl -s -o /dev/null -w '%{http_code}' -d '{}' "http://127.0.0.1:${GW}/loki/api/v1/push")"
assert_eq "...a wrong secret too" "401" \
    "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer nope' -d '{}' "http://127.0.0.1:${GW}/loki/api/v1/push")"
out="$(curl -fsS "${auth[@]}" "http://127.0.0.1:${GW}/loki/api/v1/query_range?query=x")"
assert_eq "with it, the query reaches Loki as it came" "/loki/api/v1/query_range?query=x" "$(jq -r .path <<<"$out")"
assert_eq "...without the secret" "" "$(jq -r .auth <<<"$out")"
assert_eq "no other Loki path is reachable" "404" \
    "$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" "http://127.0.0.1:${GW}/loki/api/v1/delete")"
assert_eq "/ready is Loki's, with no key" "/ready" "$(curl -fsS "http://127.0.0.1:${GW}/ready" | jq -r .path)"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    cat "${TMP}/gw.log"
    exit 1
fi
