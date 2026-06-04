#!/usr/bin/env bash
# test-compose.sh — unit tests for src/generate-compose.ts.
#
# Black-box: builds throwaway fixture repos under a temp dir, runs the real
# generate-compose.ts via tsx against them, and asserts the merged
# docker-compose.yml / master .env. Covers service discovery, relative-path
# adjustment, named/absolute volumes left alone, NFS→bind conversion (and the
# opt-out when an NFS server is configured), the network mode, the empty case,
# and archiving of an existing compose file.
#
# Needs tsx + js-yaml — only present inside existential-adhoc. Skips cleanly
# elsewhere. Read-only re: the real repo. Invoked by ./existential.sh test.

set -euo pipefail

GC="/src/generate-compose.ts"

if ! command -v tsx >/dev/null 2>&1 || [[ ! -f "$GC" ]]; then
    echo "skipped — tsx/generate-compose not available (run inside existential-adhoc)"
    exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

assert_contains()     { if grep -qF -- "$2" <<<"$3"; then _ok "$1"; else _fail "$1" "missing: $2"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<<"$3"; then _fail "$1" "unexpected: $2"; else _ok "$1"; fi; }
assert_file()         { if [[ -f "$2" ]]; then _ok "$1"; else _fail "$1" "no such file: $2"; fi; }
assert_no_file()      { if [[ -f "$2" ]]; then _fail "$1" "unexpected file: $2"; else _ok "$1"; fi; }

# Fresh fixture repo with one service (services/foo) exercising every volume
# shape: relative bind, named volume, absolute path, and an NFS volume.
new_repo() {
    local d; d="$(mktemp -d "$TMP/repo.XXXXXX")"
    mkdir -p "$d/services/foo"
    cat > "$d/services/foo/docker-compose.yml" <<'YAML'
services:
  foo:
    image: foo:1
    volumes:
      - ./data:/data
      - named_vol:/cache
      - /abs/host:/abs
      - foo_nfs:/srv
volumes:
  foo_nfs:
    driver_opts:
      type: nfs
      o: "addr=1.2.3.4,rw"
      device: ":/export/foo"
  named_vol: {}
YAML
    echo "$d"
}

# ── Enabled service: merge + path adjustment + NFS→bind ───────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\n' > "$repo/.env.shared"
err="$(tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" 2>&1 >/dev/null)" || true
assert_contains "reports the enabled service" "Enabled (1): services/foo" "$err"
assert_file "writes docker-compose.yml" "$repo/docker-compose.yml"
assert_file "writes master .env" "$repo/.env"

compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "merged service present" "foo:" "$compose"
assert_contains "relative bind rewritten under service dir" "./services/foo/data:/data" "$compose"
assert_contains "named volume left unchanged" "named_vol:/cache" "$compose"
assert_contains "absolute path left unchanged" "/abs/host:/abs" "$compose"
assert_contains "NFS volume converted to bind (o: bind)" "o: bind" "$compose"
assert_contains "NFS bind device points at host repo" "device: /host/realrepo/volumes/foo_nfs" "$compose"
assert_not_contains "converted volume no longer NFS" "type: nfs" "$compose"
assert_contains "default network is a bridge" "driver: bridge" "$compose"

envout="$(cat "$repo/.env" 2>/dev/null || true)"
assert_contains "master .env carries the do-not-edit header" "DO NOT EDIT" "$envout"

# ── NFS kept when an NFS server is configured ─────────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\nEXIST_NFS_SERVER_ADDRESS=1.2.3.4\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" >/dev/null 2>&1 || true
compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "NFS volume kept when NFS server set" "type: nfs" "$compose"
assert_not_contains "NFS volume not converted to bind when NFS server set" "o: bind" "$compose"

# ── External network mode ─────────────────────────────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\nEXIST_NETWORK_EXTERNAL=true\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true
compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "EXIST_NETWORK_EXTERNAL=true marks network external" "external: true" "$compose"

# ── No services enabled ───────────────────────────────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=false\n' > "$repo/.env.shared"
rc=0
err="$(tsx "$GC" "$repo" docker-compose.yml 2>&1 >/dev/null)" || rc=$?
assert_contains "empty selection reports nothing enabled" "No services enabled" "$err"
[[ "$rc" -eq 0 ]] && _ok "empty selection exits 0" || _fail "empty selection exits 0" "got rc=$rc"
assert_no_file "no compose written when nothing enabled" "$repo/docker-compose.yml"

# ── Existing compose is archived, not clobbered ───────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true   # first write
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true   # second → archive first
archived="$(find "$repo" -maxdepth 1 -name 'docker-compose-*.yml' -type f 2>/dev/null | head -1)"
if [[ -n "$archived" ]]; then _ok "previous compose archived on regeneration"
else _fail "previous compose archived on regeneration" "no docker-compose-*.yml found"; fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
