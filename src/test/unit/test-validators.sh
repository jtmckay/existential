#!/usr/bin/env bash
# test-validators.sh — opposite-tests for the TS validators.
#
# validate-conventions.ts and check-drift.ts are the guards the audit caught
# "passing vacuously" (pointed at nonexistent paths, validated nothing, exited
# 0). A validator is only trustworthy if it FAILS on bad input — so this builds
# deliberately-violating fixture trees, runs each validator against them
# (they take the repo root as argv[2]), and asserts a non-zero exit; plus a
# clean fixture to confirm it still passes.
#
# Needs tsx — only inside existential-adhoc. Skips cleanly on the host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONV="$SCRIPT_DIR/validate-conventions.ts"
DRIFT="$SCRIPT_DIR/check-drift.ts"

if ! command -v tsx >/dev/null 2>&1; then
    echo "skipped — tsx not available (run inside existential-adhoc)"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

rc_of() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
expect_fail() { [ "$(rc_of "${@:2}")" -ne 0 ] && _ok "$1" || _fail "$1" "expected non-zero exit, got 0"; }
expect_pass() { [ "$(rc_of "${@:2}")" -eq 0 ] && _ok "$1" || _fail "$1" "expected zero exit, got non-zero"; }

mkfix() { local d; d="$(mktemp -d "$TMP/fix.XXXXXX")"; echo "$d"; }

# ── validate-conventions.ts ───────────────────────────────────────────────────
bad="$(mkfix)"; mkdir -p "$bad/ai/foo"
printf 'services:\n  foo:\n    container_name: BadCaps\n' > "$bad/ai/foo/docker-compose.exist.yml"
expect_fail "conventions: rejects non-lowercase container_name" tsx "$CONV" "$bad"

bad2="$(mkfix)"; mkdir -p "$bad2/ai/foo"
printf 'services:\n  foo:\n    container_name: notprefixed\n' > "$bad2/ai/foo/docker-compose.exist.yml"
expect_fail "conventions: rejects container_name not prefixed by slug" tsx "$CONV" "$bad2"

clean="$(mkfix)"; mkdir -p "$clean/ai/foo"
printf 'services:\n  foo:\n    container_name: foo\n' > "$clean/ai/foo/docker-compose.exist.yml"
expect_pass "conventions: accepts a clean tree" tsx "$CONV" "$clean"

baduser="$(mkfix)"; mkdir -p "$baduser/ai/foo"
printf 'services:\n  foo:\n    container_name: foo\n    user: "1000:1000"\n' > "$baduser/ai/foo/docker-compose.exist.yml"
expect_fail "conventions: rejects hardcoded user: 1000:1000" tsx "$CONV" "$baduser"

baduidenv="$(mkfix)"; mkdir -p "$baduidenv/ai/foo"
printf 'services:\n  foo:\n    container_name: foo\n    environment:\n      HERMES_UID: "1000"\n' > "$baduidenv/ai/foo/docker-compose.exist.yml"
expect_fail "conventions: rejects hardcoded uid/gid env" tsx "$CONV" "$baduidenv"

cleanuid="$(mkfix)"; mkdir -p "$cleanuid/ai/foo"
printf 'services:\n  foo:\n    container_name: foo\n    user: "${EXIST_PUID:-1000}:${EXIST_PGID:-1000}"\n' > "$cleanuid/ai/foo/docker-compose.exist.yml"
expect_pass "conventions: accepts the EXIST_PUID user form" tsx "$CONV" "$cleanuid"

# ── networking: piHole wildcard + Caddy-as-source-of-truth ───────────────────
# piHole present but missing the single wildcard DNS record → fail.
badph="$(mkfix)"; mkdir -p "$badph/hosting/pihole"
cat > "$badph/hosting/pihole/docker-compose.exist.yml" <<'EOF'
services:
  pihole:
    container_name: pihole
    environment:
      FTLCONF_dns_listeningMode: 'ALL'
EOF
expect_fail "conventions: rejects piHole missing the wildcard DNS record" tsx "$CONV" "$badph"

# .env.exist.shared present but EXIST_DOMAIN undefined → fail.
baddom="$(mkfix)"
printf 'EXIST_LOCAL_HOST_IP=1.2.3.4\n' > "$baddom/.env.exist.shared"
expect_fail "conventions: rejects .env.shared missing EXIST_DOMAIN" tsx "$CONV" "$baddom"

# Dashy links a slug that has no Caddy block (Caddy is the source of truth) → fail.
baddash="$(mkfix)"; mkdir -p "$baddash/services/dashy" "$baddash/hosting/caddy"
cat > "$baddash/services/dashy/dashy-conf.exist.yml" <<'EOF'
sections:
  - items:
      - title: Ghost
        url: https://ghost.EXIST_DOMAIN
EOF
printf '# no reverse_proxy blocks\n' > "$baddash/hosting/caddy/Caddyfile.exist.Caddyfile"
expect_fail "conventions: rejects Dashy item with no Caddy block" tsx "$CONV" "$baddash"

# A clean networking tree (wildcard record + EXIST_DOMAIN + matching Caddy/Dashy).
cleannet="$(mkfix)"
mkdir -p "$cleannet/hosting/pihole" "$cleannet/hosting/caddy" "$cleannet/services/dashy" "$cleannet/ai/foo"
printf 'EXIST_DOMAIN=x.internal\nEXIST_LOCAL_HOST_IP=1.2.3.4\n' > "$cleannet/.env.exist.shared"
cat > "$cleannet/hosting/pihole/docker-compose.exist.yml" <<'EOF'
services:
  pihole:
    container_name: pihole
    environment:
      FTLCONF_misc_dnsmasq_lines: 'address=/${EXIST_DOMAIN}/${EXIST_LOCAL_HOST_IP}'
EOF
printf 'services:\n  foo:\n    container_name: foo\n' > "$cleannet/ai/foo/docker-compose.exist.yml"
cat > "$cleannet/hosting/caddy/Caddyfile.exist.Caddyfile" <<'EOF'
foo.{$CADDY_DOMAIN} {
  reverse_proxy foo:8080
}
EOF
cat > "$cleannet/services/dashy/dashy-conf.exist.yml" <<'EOF'
sections:
  - items:
      - title: Foo
        url: https://foo.EXIST_DOMAIN
EOF
expect_pass "conventions: accepts a clean networking tree" tsx "$CONV" "$cleannet"

# ── decree config.exist.yml — commands block ─────────────────────────────────
baddecree="$(mkfix)"; mkdir -p "$baddecree/ai/foo/decree"
printf 'routine_source: /work/.decree/shared_routines\nmax_attempts: 3\n' \
  > "$baddecree/ai/foo/decree/config.exist.yml"
expect_fail "conventions: rejects decree config missing commands block" tsx "$CONV" "$baddecree"

cleandecree="$(mkfix)"; mkdir -p "$cleandecree/ai/foo/decree"
printf 'routine_source: /work/.decree/shared_routines\ncommands:\n  ai_router: opencode run {prompt}\n  ai_interactive: opencode\nmax_attempts: 3\n' \
  > "$cleandecree/ai/foo/decree/config.exist.yml"
expect_pass "conventions: accepts decree config with commands block" tsx "$CONV" "$cleandecree"

# ── check-drift.ts ────────────────────────────────────────────────────────────
drifted="$(mkfix)"
printf 'alpha\nbeta\n'  > "$drifted/x.exist.txt"
printf 'alpha\nGAMMA\n' > "$drifted/x.txt"          # line 2 differs, no placeholder → drift
expect_fail "drift: detects a rendered file diverging from its template" tsx "$DRIFT" "$drifted"

insync="$(mkfix)"
printf 'alpha\nbeta\n' > "$insync/x.exist.txt"
printf 'alpha\nbeta\n' > "$insync/x.txt"
expect_pass "drift: passes when rendered matches template" tsx "$DRIFT" "$insync"

# ── Self-check canary ─────────────────────────────────────────────────────────
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
