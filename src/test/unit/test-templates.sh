#!/usr/bin/env bash
# test-templates.sh — unit tests for src/templates.sh render_template().
#
# Sources templates.sh (its main block is guarded, so sourcing only defines
# functions), stubs the secret generators for deterministic output, points
# REPO_DIR at a throwaway fake repo, and asserts that render_template resolves
# every placeholder class correctly. These cover the bugs that bit us:
#   - EXIST_CLI on line 1 (the (( block_start++ )) set -e landmine)
#   - & in a resolved value (sed replacement re-inserting the token / looping)
#   - rendering .env.shared itself must NOT self-substitute its own keys
#
# All renders run with stdin from /dev/null, so EXIST_CLI is non-interactive
# (falls back to its default) and the test never blocks on a prompt.
#
# Read-only re: the real repo. Runs inside existential-adhoc (templates.sh
# sources the generators from /src/utils). Invoked by ./existential.sh test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$(cd "${SCRIPT_DIR}/../.." && pwd)/templates.sh"

# Needs the generators templates.sh sources at /src/utils — only present inside
# the adhoc container. Skip cleanly elsewhere so bulk runs stay safe.
if [[ ! -r /src/utils/generate_password.sh ]]; then
    echo "skipped — generators not available (run inside existential-adhoc)"
    exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── Counters / asserts ────────────────────────────────────────────────────────

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

assert_eq()           { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$(printf '%q' "$2")  got=$(printf '%q' "$3")"; fi; }
assert_contains()     { if grep -qF -- "$2" <<<"$3"; then _ok "$1"; else _fail "$1" "missing: $2"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<<"$3"; then _fail "$1" "unexpected: $2"; else _ok "$1"; fi; }

# ── Load functions + deterministic stubs ──────────────────────────────────────

REPO_DIR="$TMP"
# shellcheck disable=SC1090
. "$TEMPLATES"
REPO_DIR="$TMP"

# File-backed counters so each call yields a distinct value even though
# render_template invokes these inside $( ) command-substitution subshells.
_next() { local n; n=$(( $(cat "$TMP/.c.$1" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$TMP/.c.$1"; printf '%s' "$n"; }
gen_password() { printf 'PW%02d_aaaaaaaaaaaaaaaaaa' "$(_next pw)"; }
gen_hex()      { printf 'HX%02d_%s' "$(_next hx)" "${1:-32}"; }
gen_uuid()     { printf 'uuid-%04d' "$(_next uuid)"; }

cat > "$TMP/.env.shared" <<'EOF'
EXIST_USER=bob
EXIST_USERNAME=alice
EXIST_NTFY_URL=http://ntfy:80
EXIST_AMP=a&b
EOF

# Render a template file (non-interactive) and print the resolved content.
render()     { render_template "$1" "${2:-$TMP/out}" </dev/null; }

# Like render() but bounded by a timeout and run in a child shell, so a
# regression that crashes (set -e) or loops forever surfaces as a FAIL with a
# non-zero rc instead of aborting or hanging the whole suite.
export REPO_DIR
export -f render_template gen_password gen_hex gen_uuid _next
try_render() {
    timeout 10 bash -c 'render_template "$1" "$2" </dev/null 2>/dev/null' _ "$1" "${2:-$TMP/out}"
}

# ── EXIST_* substitution ──────────────────────────────────────────────────────

printf 'USER=EXIST_USERNAME\nNTFY=${EXIST_NTFY_URL}\n' > "$TMP/t_subst"
out="$(render "$TMP/t_subst")"
assert_contains "bare EXIST_USERNAME substituted from .env.shared" "USER=alice" "$out"
assert_contains '${EXIST_NTFY_URL} substituted' "NTFY=http://ntfy:80" "$out"

# ── Regression (M-4): a shorter key must not clobber a longer one ──────────────
# EXIST_USER (bob) is a prefix of EXIST_USERNAME (alice). Longest-first ordering
# + a trailing word boundary must keep EXIST_USERNAME → alice, never "bobNAME".
printf 'A=${EXIST_USERNAME}\nB=EXIST_USERNAME\nC=${EXIST_USER}\n' > "$TMP/t_prefix"
out="$(render "$TMP/t_prefix")"
assert_contains "longer key \${EXIST_USERNAME} wins over prefix EXIST_USER" "A=alice" "$out"
assert_contains "bare longer key EXIST_USERNAME wins over prefix EXIST_USER" "B=alice" "$out"
assert_contains "shorter key \${EXIST_USER} still resolves" "C=bob" "$out"
assert_not_contains "prefix key did not corrupt the longer one" "bobNAME" "$out"

# ── Generated secrets, unique per occurrence ──────────────────────────────────

printf 'A=EXIST_24_CHAR_PASSWORD\nB=EXIST_24_CHAR_PASSWORD\n' > "$TMP/t_gen"
out="$(render "$TMP/t_gen")"
a="$(grep '^A=' <<<"$out" | cut -d= -f2)"
b="$(grep '^B=' <<<"$out" | cut -d= -f2)"
assert_not_contains "no password token remains" "EXIST_24_CHAR_PASSWORD" "$out"
if [[ -n "$a" && "$a" != "$b" ]]; then _ok "two password placeholders get distinct values"
else _fail "two password placeholders get distinct values" "a=$a b=$b"; fi

# ── EXIST_CLI: non-interactive default is empty ───────────────────────────────

printf '# Default email\nEMAIL=EXIST_CLI\n' > "$TMP/t_cli"
out="$(render "$TMP/t_cli")"
assert_contains "EXIST_CLI with no default resolves empty (no tty)" "EMAIL=" "$out"
assert_not_contains "EXIST_CLI token consumed" "EXIST_CLI" "$out"

# ── EXIST_CLI: DEFAULT_FROM falls back to an earlier resolved value ────────────

printf 'HOST=EXIST_USERNAME\n# DEFAULT_FROM: HOST\nPEER=EXIST_CLI\n' > "$TMP/t_default_from"
out="$(render "$TMP/t_default_from")"
assert_contains "DEFAULT_FROM resolves to earlier field's value" "PEER=alice" "$out"

# ── Regression: EXIST_CLI on line 1 must not crash (the (( )) set -e landmine) ─

printf 'FIRST=EXIST_CLI\n' > "$TMP/t_line1"
if out="$(try_render "$TMP/t_line1")"; then
    assert_contains "line-1 EXIST_CLI resolves without crashing" "FIRST=" "$out"
else
    _fail "line-1 EXIST_CLI resolves without crashing" "render_template exited non-zero"
fi

# ── Regression: '&' in a resolved value renders literally (no re-injection) ────

printf 'AMP=EXIST_AMP\n# DEFAULT_FROM: AMP\nX=EXIST_CLI\n' > "$TMP/t_amp"
if out="$(try_render "$TMP/t_amp")"; then
    assert_contains "ampersand value renders literally via DEFAULT_FROM" "X=a&b" "$out"
    assert_not_contains "no token remains after & value (no infinite loop)" "EXIST_CLI" "$out"
else
    _fail "ampersand value renders literally via DEFAULT_FROM" "render_template exited non-zero (likely looped)"
fi

# ── Rendering .env.shared itself must NOT self-substitute its own keys ─────────

printf 'EXIST_USERNAME=EXIST_CLI\n' > "$TMP/t_self"
out="$(render_template "$TMP/t_self" "$TMP/.env.shared" </dev/null)"
assert_contains ".env.shared render keeps its own key name" "EXIST_USERNAME=" "$out"
assert_not_contains ".env.shared render does not inject key's value" "alice=" "$out"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
