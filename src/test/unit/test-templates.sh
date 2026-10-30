#!/usr/bin/env bash
# test-templates.sh — unit tests for src/templates.sh.
#
# Sources templates.sh (its main block is guarded, so sourcing only defines
# functions), stubs the secret generators for deterministic output, points
# REPO_DIR at a throwaway fake repo, and asserts that render_template resolves
# every placeholder class correctly. These cover the bugs that bit us:
#   - EXIST_CLI on line 1 (the (( block_start++ )) set -e landmine)
#   - & in a resolved value (sed replacement re-inserting the token / looping)
#   - rendering .env.shared itself must NOT self-substitute its own keys
#
# Also covers the _ALWAYS_RENDER carve-out (destinations regenerated every run
# rather than skipped-if-exists), the EXIST_KEEP opt-out that lets a user claim
# one of those files, the guard rail that refuses to always-render a template
# carrying prompts or generated secrets, and the rule that .env stays
# untouchable regardless.
#
# All renders run with stdin from /dev/null, so EXIST_CLI is non-interactive
# (falls back to its default) and the test never blocks on a prompt.
#
# Read-only re: the real repo. Runs inside existential-adhoc (templates.sh
# sources the generators from /src/utils). Invoked by ./existential.sh test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve both paths BEFORE sourcing templates.sh — it reassigns SCRIPT_DIR to
# REPO_DIR (the throwaway fake repo), so anything derived from it afterwards
# points into $TMP.
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
EXIST_BLANK=
EOF

# Render a template file (non-interactive) and print the resolved content.
render()     { render_template "$1" "${2:-$TMP/out}" </dev/null; }

# Like render() but bounded by a timeout and run in a child shell, so a
# regression that crashes (set -e) or loops forever surfaces as a FAIL with a
# non-zero rc instead of aborting or hanging the whole suite.
# TMP as well as REPO_DIR: the stubbed generators keep their counters in files
# under $TMP, so without it every call in the child shell writes to /.c.* — which
# fails silently, hands out the same value twice, and looks like a uniqueness bug
# in render_template rather than a missing export here.
export REPO_DIR TMP
export -f render_template gen_password gen_hex gen_uuid _next \
          _prompt_available _prompt_tty _context_above
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

# ── Regression: a BLANK .env.shared value must still substitute ────────────────
# Skipping blank values left the literal token in the rendered file, so an
# unfilled shared key shipped its own name into a container: a URL key as the
# URL, "EXIST_USERNAME" as a postgres role name. Empty is the honest
# render; a surviving placeholder never is.
printf 'A=EXIST_BLANK\nB=${EXIST_BLANK}\n' > "$TMP/t_blank"
out="$(render "$TMP/t_blank")"
assert_not_contains "blank shared value leaves no bare placeholder" "EXIST_BLANK" "$out"
# assert_eq on the extracted value, not assert_contains "A=": "A=" is a substring
# of "A=EXIST_BLANK", so a contains-check here would pass with the bug present.
assert_eq "blank shared value renders as empty (bare form)" "" "$(grep '^A=' <<<"$out" | cut -d= -f2-)"
assert_eq "blank shared value renders as empty (\${} form)" "" "$(grep '^B=' <<<"$out" | cut -d= -f2-)"

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

# ── EXIST_CLI: DEFAULT gives a literal fallback ───────────────────────────────

printf '# DEFAULT: admin\nNAME=EXIST_CLI\n' > "$TMP/t_default"
out="$(render "$TMP/t_default")"
assert_contains "DEFAULT is used when nothing is entered" "NAME=admin" "$out"

# ── Regression: EXIST_CLI on line 1 must not crash (the (( )) set -e landmine) ─

printf 'FIRST=EXIST_CLI\n' > "$TMP/t_line1"
if out="$(try_render "$TMP/t_line1")"; then
    assert_contains "line-1 EXIST_CLI resolves without crashing" "FIRST=" "$out"
else
    _fail "line-1 EXIST_CLI resolves without crashing" "render_template exited non-zero"
fi

# ── Regression: '&' in a resolved value renders literally (no re-injection) ────

printf '# DEFAULT: a&b\nX=EXIST_CLI\n' > "$TMP/t_amp"
if out="$(try_render "$TMP/t_amp")"; then
    assert_contains "ampersand value renders literally via DEFAULT" "X=a&b" "$out"
    assert_not_contains "no token remains after & value (no infinite loop)" "EXIST_CLI" "$out"
else
    _fail "ampersand value renders literally via DEFAULT" "render_template exited non-zero (likely looped)"
fi

# ── Rendering .env.shared itself must NOT self-substitute its own keys ─────────

printf 'EXIST_USERNAME=EXIST_CLI\n' > "$TMP/t_self"
out="$(render_template "$TMP/t_self" "$TMP/.env.shared" </dev/null)"
assert_contains ".env.shared render keeps its own key name" "EXIST_USERNAME=" "$out"
assert_not_contains ".env.shared render does not inject key's value" "alice=" "$out"

# ── Always-render: _renders_always path matching ──────────────────────────────

if _renders_always "$TMP/services/dashy/dashy-conf.yml"; then
    _ok "_renders_always matches the dashy destination"
else
    _fail "_renders_always matches the dashy destination" "dashy-conf.yml not in _ALWAYS_RENDER"
fi
if _renders_always "$TMP/services/mealie/docker-compose.yml"; then
    _fail "_renders_always rejects an unlisted destination" "matched something it shouldn't"
else
    _ok "_renders_always rejects an unlisted destination"
fi

# ── Always-render: overwrites an existing destination ─────────────────────────
# This is the whole point — the general skip-if-exists gate must not apply.

mkdir -p "$TMP/services/dashy"
_DCONF="$TMP/services/dashy/dashy-conf.yml"
printf 'appConfig:\n  theme: colorful\nsections:\n  - name: AI\n    items:\n      - title: Open WebUI\n        url: https://open-webui.EXIST_HOSTDOMAIN\n' \
    > "$TMP/services/dashy/dashy-conf.exist.yml"
echo 'EXIST_HOSTDOMAIN=example.test' >> "$TMP/.env.shared"
printf 'stale: true\n' > "$_DCONF"
_rc=0; _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" >/dev/null || _rc=$?
assert_eq "always-render returns 2 (regenerated), not 1 (skipped)" "2" "$_rc"
out="$(cat "$_DCONF")"
assert_not_contains "always-render replaced the stale destination" "stale: true" "$out"
assert_contains "always-render stamped the DO-NOT-EDIT header" \
    "DO NOT EDIT — regenerated on every ./existential.sh run" "$out"
assert_contains "always-render resolved placeholders" "https://open-webui.example.test" "$out"

# The header marker is what check-drift.ts keys off to skip these files. If the
# wording changes here, isGenerated() in check-drift.ts must change with it.
assert_contains "header names the base template" "Base: services/dashy/dashy-conf.exist.yml" "$out"
assert_contains "header carries the EXIST_KEEP opt-out, defaulted off" \
    "# EXIST_KEEP: false" "$out"

# ── Always-render: the .env never-overwrite guard still wins ──────────────────
# .env is checked before _ALWAYS_RENDER, so even if someone lists one it stays
# untouched — a rendered .env holds answers that can't be regenerated.

printf 'SECRET=keepme\n' > "$TMP/.env"
printf 'SECRET=EXIST_USERNAME\n' > "$TMP/.env.exist"
_ALWAYS_RENDER+=(".env")
_rc=0; _process_one_template "$TMP/.env.exist" >/dev/null || _rc=$?
assert_eq ".env stays skipped even when listed in _ALWAYS_RENDER" "1" "$_rc"
assert_eq ".env contents untouched" "SECRET=keepme" "$(cat "$TMP/.env")"
unset '_ALWAYS_RENDER[-1]'

# ── Always-render: guard rail rejects prompts / generated secrets ─────────────
# An always-rendered file is overwritten with no backup every run, so a secret
# would rotate underneath whatever consumed it and EXIST_CLI would re-prompt.

printf 'appConfig:\n  token: EXIST_32_CHAR_HEX_KEY\n' \
    > "$TMP/services/dashy/dashy-conf.exist.yml"
if ( _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" ) >/dev/null 2>&1; then
    _fail "always-render template with a secret token exits non-zero" "it was accepted"
else
    _ok "always-render template with a secret token exits non-zero"
fi

printf 'appConfig:\n  who: EXIST_CLI\n' > "$TMP/services/dashy/dashy-conf.exist.yml"
if ( _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" ) >/dev/null 2>&1; then
    _fail "always-render template with EXIST_CLI exits non-zero" "it was accepted"
else
    _ok "always-render template with EXIST_CLI exits non-zero"
fi

# ── Always-render: the EXIST_KEEP opt-out ────────────────────────────────────
# Flipping the header line to true claims the file. From then on it is the
# user's and is never regenerated.

printf 'appConfig:\n  theme: colorful\n' > "$TMP/services/dashy/dashy-conf.exist.yml"
printf '# EXIST_KEEP: true\nappConfig:\n  theme: MINE\n' > "$_DCONF"

_rc=0; _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" >/dev/null || _rc=$?
assert_eq "EXIST_KEEP: true makes always-render skip (returns 1)" "1" "$_rc"
assert_contains "EXIST_KEEP: true left the user's content intact" \
    "theme: MINE" "$(cat "$_DCONF")"

# ── No re-render override ────────────────────────────────────────────────────
# `--force` was removed: it overwrote with no undo and never said what it would
# touch (./existential.sh reset archives instead). A leftover FORCE in the
# environment must therefore do nothing — this fails if the branch comes back.

printf 'fresh: yes\n' > "$TMP/norender.exist.txt"
printf 'mine: yes\n'  > "$TMP/norender.txt"
_rc=0; FORCE=true _process_one_template "$TMP/norender.exist.txt" >/dev/null || _rc=$?
assert_eq "a stray FORCE=true does not re-render (returns 1)" "1" "$_rc"
assert_contains "a stray FORCE=true left the existing file intact" \
    "mine: yes" "$(cat "$TMP/norender.txt")"

# The default stamped value must NOT opt out, or nothing would ever regenerate.
printf '# EXIST_KEEP: false\nappConfig:\n  theme: OLD\n' > "$_DCONF"
_rc=0; _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" >/dev/null || _rc=$?
assert_eq "EXIST_KEEP: false still regenerates (returns 2)" "2" "$_rc"
assert_not_contains "EXIST_KEEP: false was overwritten" "theme: OLD" "$(cat "$_DCONF")"

# Re-rendering must not stack headers: content comes from the template, so the
# previous run's header is discarded rather than wrapped inside a new one.
_rc=0; _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" >/dev/null || _rc=$?
assert_eq "repeat render stamps exactly one header" \
    "1" "$(grep -c 'EXIST_KEEP' "$_DCONF")"

# Only the header counts — the same words further down are just content.
{ printf '# padding\n%.0s' $(seq 1 25); printf '# EXIST_KEEP: true\n'; } > "$_DCONF"
_rc=0; _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" >/dev/null || _rc=$?
assert_eq "EXIST_KEEP below the header does not opt out" "2" "$_rc"

# A directory template is cp -r'd, which would nest into an existing destination
# on the second run instead of replacing it.
rm -f "$TMP/services/dashy/dashy-conf.exist.yml"
mkdir -p "$TMP/services/dashy/dashy-conf.exist.yml"
if ( _process_one_template "$TMP/services/dashy/dashy-conf.exist.yml" ) >/dev/null 2>&1; then
    _fail "always-render rejects a directory template" "it was accepted"
else
    _ok "always-render rejects a directory template"
fi
rmdir "$TMP/services/dashy/dashy-conf.exist.yml"

# ── Key-level reconcile of rendered .env files ────────────────────────────────
# A rendered .env is never overwritten, so a key ADDED to the template upstream
# would otherwise never reach an install that already rendered it. These cover
# the four invariants that make append-on-every-run safe.

mkdir -p "$TMP/services/recon"
_RSRC="$TMP/services/recon/.env.exist"
_RDST="$TMP/services/recon/.env"

# A new static key arrives with its documentation, and nothing already in the
# file moves — including a value the user edited away from the template default.
cat > "$_RSRC" <<'EOF'
# What the old key does.
RECON_OLD=default-value

# What the new key does, and the one thing that breaks if it is wrong.
RECON_NEW=new-default
EOF
printf '# What the old key does.\nRECON_OLD=user-edited-this\n' > "$_RDST"
out="$(_reconcile_env_keys "$_RSRC" "$_RDST")"
assert_contains "new static key appended"            "RECON_NEW=new-default"    "$(cat "$_RDST")"
assert_contains "the key's own comment came with it" "one thing that breaks"    "$(cat "$_RDST")"
assert_contains "user's edited value survives"       "RECON_OLD=user-edited-this" "$(cat "$_RDST")"
assert_not_contains "template default did not overwrite it" "RECON_OLD=default-value" "$(cat "$_RDST")"
assert_contains "the added key is reported"          "+ RECON_NEW"              "$out"

# A new key whose template value is a generated secret gets a real one — a newly
# arrived service needs its own credential, not a shared or literal placeholder.
printf 'RECON_OLD=default-value\nRECON_KEY=EXIST_32_CHAR_HEX_KEY\n' > "$_RSRC"
printf 'RECON_OLD=user-edited-this\n' > "$_RDST"
_reconcile_env_keys "$_RSRC" "$_RDST" >/dev/null
assert_contains "new secret key got a generated value" "RECON_KEY=HX" "$(cat "$_RDST")"
assert_not_contains "the literal placeholder never lands" "EXIST_32_CHAR_HEX_KEY" "$(cat "$_RDST")"

# A new EXIST_CLI key is a question whose answer is the user's. It arrives blank
# — the established "not yet answered" sentinel — rather than guessed from its
# DEFAULT, which could contradict the user.
printf 'RECON_OLD=default-value\n# DEFAULT: guessed\nRECON_ASK=EXIST_CLI\n' > "$_RSRC"
printf 'RECON_OLD=user-edited-this\n' > "$_RDST"
out="$(_reconcile_env_keys "$_RSRC" "$_RDST")"
assert_eq "new EXIST_CLI key appended blank" "RECON_ASK=" "$(grep '^RECON_ASK=' "$_RDST")"
assert_contains "EXIST_CLI key flagged as needing a value" "needs a value" "$out"

# A renamed key carries what the user set under its old name. EXIST_OLLAMA_URL*
# held ollama's root, so the value arrives as the /v1 base the new key means; a
# blank old key leaves the new one at its template value.
cp "$TMP/.env.shared" "$TMP/.env.shared.saved"
printf 'EXIST_MODEL_URL=http://ollama:11434/v1\nEXIST_MODEL_URL_CHAT=\nEXIST_MODEL_URL_EMBED=\n' > "$TMP/.env.exist.shared"
printf 'EXIST_OLLAMA_URL=http://bigbox:11434\nEXIST_OLLAMA_URL_CHAT=http://chatbox:8080/v1/\nEXIST_OLLAMA_URL_EMBED=\n' > "$TMP/.env.shared"
_reconcile_env_keys "$TMP/.env.exist.shared" "$TMP/.env.shared" >/dev/null
assert_eq "an old global model URL takes effect under the new key" \
    "EXIST_MODEL_URL=http://bigbox:11434/v1" "$(grep '^EXIST_MODEL_URL=' "$TMP/.env.shared")"
assert_eq "an old role URL that already ended /v1 is not doubled" \
    "EXIST_MODEL_URL_CHAT=http://chatbox:8080/v1" "$(grep '^EXIST_MODEL_URL_CHAT=' "$TMP/.env.shared")"
assert_eq "a blank old role key leaves the new one blank" \
    "EXIST_MODEL_URL_EMBED=" "$(grep '^EXIST_MODEL_URL_EMBED=' "$TMP/.env.shared")"
mv "$TMP/.env.shared.saved" "$TMP/.env.shared"; rm -f "$TMP/.env.exist.shared"

# Blank is load-bearing (EXIST_VRAM_GB = not yet asked, EXIST_MODEL_URL_<ROLE> =
# fall back to the global URL), so a key that is present and empty is left alone.
printf 'RECON_BLANK=has-a-default\n' > "$_RSRC"
printf 'RECON_BLANK=\n' > "$_RDST"
_reconcile_env_keys "$_RSRC" "$_RDST" >/dev/null
assert_eq "an existing blank value is never filled" "RECON_BLANK=" "$(grep '^RECON_BLANK=' "$_RDST")"

# Append-only in the other direction too: a key the user added and the template
# does not have is not the reconciler's business. `validate drift` reports those.
printf 'RECON_OLD=x\n' > "$_RSRC"
printf 'RECON_OLD=x\nRECON_MINE=keep-me\n' > "$_RDST"
_reconcile_env_keys "$_RSRC" "$_RDST" >/dev/null
assert_contains "a locally added key is never removed" "RECON_MINE=keep-me" "$(cat "$_RDST")"

# A file that does not end in a newline must not get the stamp glued to its last
# value.
printf 'RECON_OLD=x\nRECON_TAIL=t\n' > "$_RSRC"
printf 'RECON_OLD=mine' > "$_RDST"
_reconcile_env_keys "$_RSRC" "$_RDST" >/dev/null
assert_eq "no trailing newline does not corrupt the last value" \
    "RECON_OLD=mine" "$(grep '^RECON_OLD=' "$_RDST")"
assert_contains "and the new key still lands" "RECON_TAIL=t" "$(cat "$_RDST")"

# The regression that matters most, because it runs on every single invocation:
# an install that is already current must come out byte-identical and silent.
printf 'RECON_OLD=x\n' > "$_RSRC"
printf 'RECON_OLD=mine\n' > "$_RDST"
_before="$(md5sum < "$_RDST")"
out="$(_reconcile_env_keys "$_RSRC" "$_RDST")"
assert_eq "no new keys leaves the file byte-identical" "$_before" "$(md5sum < "$_RDST")"
assert_eq "no new keys prints nothing"                 ""        "$out"
assert_not_contains "no new keys stamps no header" "$_RECONCILE_MARKER" "$(cat "$_RDST")"

# Wiring: the .env guard in _process_one_template still refuses to overwrite
# (returns 1) but reconciles on the way past.
printf 'RECON_OLD=x\nRECON_HOOKED=yes\n' > "$_RSRC"
printf 'RECON_OLD=mine\n' > "$_RDST"
_rc=0; _process_one_template "$_RSRC" >/dev/null || _rc=$?
assert_eq ".env is still render-once (returns 1)" "1" "$_rc"
assert_contains "the .env guard reconciled on the way past" "RECON_HOOKED=yes" "$(cat "$_RDST")"
assert_contains "the user's value was still not overwritten" "RECON_OLD=mine" "$(cat "$_RDST")"

# A key appended to .env.shared has to be visible for the REST of the same run.
# The case that bites is a new EXIST_IS_<CATEGORY>_<SLUG>: service_is_enabled
# decides from the loaded environment whether a service dir is even visited, so
# without a reload after reconcile a newly arrived service would be skipped for a
# whole run and only appear on the next one.
mkdir -p "$TMP/ai/newsvc"
printf 'EXIST_DOMAIN=example.test\nEXIST_IS_AI_NEWSVC=true\n' > "$TMP/.env.exist.shared"
printf 'EXIST_DOMAIN=example.test\n' > "$TMP/.env.shared"
printf 'NEWSVC_URL=https://newsvc.${EXIST_DOMAIN}\n' > "$TMP/ai/newsvc/.env.exist"
_main >/dev/null 2>&1 || true
assert_contains "a newly appended EXIST_IS_* flag lands in .env.shared" \
    "EXIST_IS_AI_NEWSVC=true" "$(cat "$TMP/.env.shared")"
if [[ -f "$TMP/ai/newsvc/.env" ]]; then
    _ok "the service it enables renders in the same run"
    assert_contains "and renders against the existing shared values" \
        "NEWSVC_URL=https://newsvc.example.test" "$(cat "$TMP/ai/newsvc/.env")"
else
    _fail "the service it enables renders in the same run" \
        "ai/newsvc/.env absent — the new flag was not reloaded"
fi

# ── A first run asks one thing: Core or none ──────────────────────────────────
#
# .env.exist.shared itself asks nothing: the login and email ship blank and are
# asked when an enabled service first uses them. Checked on the real templates,
# since that is where a question would creep back in.
_REAL=/repo; [[ -f "$_REAL/.env.exist.shared" ]] || _REAL="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
assert_eq ".env.exist.shared asks nothing" "" "$(grep -E '=EXIST_CLI$' "$_REAL/.env.exist.shared")"
out="$(render "$_REAL/.env.exist.shared" "$TMP/.env.shared")"
for _k in EXIST_USERNAME EXIST_PASSWORD EXIST_EMAIL; do
    assert_eq "${_k} ships blank (not yet asked)" "${_k}=" "$(grep "^${_k}=" <<<"$out")"
done
for _svc in $(sed -n 's/^EXIST_IS_SERVICES_\(.*\)=true$/\1/p' "$_REAL/.env.exist.shared"); do
    _svc="${_svc,,}"; _svc="services/${_svc//_/-}"
    if grep -rqsE --include='*.exist*' 'EXIST_EMAIL|EXIST_CLI' "$_REAL/$_svc"; then
        _fail "Core's ${_svc} asks nothing and needs no email"
    else
        _ok "Core's ${_svc} asks nothing and needs no email"
    fi
done

printf 'EXIST_IS_AI_X=true\nEXIST_IS_SERVICES_Y=true\nEXIST_IS_SERVICES_Z=false\n' > "$TMP/.env.shared"
( _prompt_available() { true; }; command() { return 1; }; _prompt_tty() { printf none; }
  _ask_core_or_none ) >/dev/null 2>&1 </dev/null
assert_eq "none turns every flag off" "" "$(grep '=true$' "$TMP/.env.shared")"
printf 'EXIST_IS_AI_X=true\n' > "$TMP/.env.shared"
( _prompt_available() { true; }; command() { return 1; }; _prompt_tty() { printf ''; }
  _ask_core_or_none ) >/dev/null 2>&1 </dev/null
assert_eq "Enter keeps Core" "EXIST_IS_AI_X=true" "$(cat "$TMP/.env.shared")"
_ask_core_or_none >/dev/null 2>&1 </dev/null
assert_eq "no terminal keeps Core" "EXIST_IS_AI_X=true" "$(cat "$TMP/.env.shared")"

printf '# Who you are\n# DEFAULT: admin\nWHO=EXIST_CLI\n' > "$TMP/t_default"
assert_contains "# DEFAULT: is the literal default when nobody answers" "WHO=admin" "$(render "$TMP/t_default")"

# The login and email are asked once, the first time an enabled service uses them.
mkdir -p "$TMP/ai/mailsvc"
printf 'MAILSVC_ADMIN_EMAIL=EXIST_EMAIL\nMAILSVC_USER=EXIST_USERNAME\nMAILSVC_PW=${EXIST_PASSWORD}\n' > "$TMP/ai/mailsvc/.env.exist"
_blank() { printf 'EXIST_USERNAME=\nEXIST_PASSWORD=\nEXIST_EMAIL=\nEXIST_IS_AI_MAILSVC=%s\n' "$1" > "$TMP/.env.shared"; }
_ask() { ( _prompt_available() { true; }
           _prompt_tty() { echo asked >> "$TMP/.asked"; printf 'me@example.test'; }
           _reload_env_shared; _ask_if_needed EXIST_EMAIL ) >/dev/null 2>&1 </dev/null; }
_blank false
_ask
assert_eq "no enabled service needs an email → not asked" "" "$(cat "$TMP/.asked" 2>/dev/null)"
assert_contains "and EXIST_EMAIL stays blank" "EXIST_EMAIL=" "$(grep '^EXIST_EMAIL=' "$TMP/.env.shared")"
( _reload_env_shared; for _k in EXIST_USERNAME EXIST_PASSWORD; do _ask_if_needed "$_k"; done ) >/dev/null 2>&1 </dev/null
assert_eq "...nor a login" "EXIST_USERNAME= EXIST_PASSWORD=" "$(grep -E '^EXIST_(USERNAME|PASSWORD)=' "$TMP/.env.shared" | xargs)"
sed -i 's/^EXIST_IS_AI_MAILSVC=false$/EXIST_IS_AI_MAILSVC=true/' "$TMP/.env.shared"
_ask
assert_eq "an enabled service that uses it → asked once" "asked" "$(cat "$TMP/.asked" 2>/dev/null)"
assert_eq "the answer is filled in" "EXIST_EMAIL=me@example.test" "$(grep '^EXIST_EMAIL=' "$TMP/.env.shared")"
_ask
assert_eq "and never asked again" "asked" "$(cat "$TMP/.asked" 2>/dev/null)"
_blank true
( _reload_env_shared; for _k in EXIST_USERNAME EXIST_PASSWORD EXIST_EMAIL; do _ask_if_needed "$_k"; done ) >/dev/null 2>&1 </dev/null
assert_eq "no terminal → the username is admin" "EXIST_USERNAME=admin" "$(grep '^EXIST_USERNAME=' "$TMP/.env.shared")"
if grep -qE '^EXIST_PASSWORD=.{8,}$' "$TMP/.env.shared"; then _ok "no terminal → a password is generated"
else _fail "no terminal → a password is generated" "$(grep '^EXIST_PASSWORD=' "$TMP/.env.shared")"; fi
assert_eq "...and the email stays blank" "EXIST_EMAIL=" "$(grep '^EXIST_EMAIL=' "$TMP/.env.shared")"
rm -rf "$TMP/ai/mailsvc"

# The NAS address is asked once, then a path for each nfs: true volume of an
# enabled service; a db: true volume and a disabled service are never asked.
mkdir -p "$TMP/nas/cloud" "$TMP/nas/off"
printf 'x-exist-volumes:\n  cloud_files_data: { nfs: true }\n  cloud_themes_data: { nfs: true }\n  cloud_sql_data: { db: true }\n' > "$TMP/nas/cloud/docker-compose.exist.yml"
printf 'x-exist-volumes:\n  off_data: { nfs: true }\n' > "$TMP/nas/off/docker-compose.exist.yml"
_nas() { ( unset EXIST_NFS_ADDRESS; _prompt_available() { true; }
           _prompt_tty() { echo "$1 [$2]" >> "$TMP/.nasked"; sed -n 1p "$TMP/.answers"; sed -i 1d "$TMP/.answers"; }
           _reload_env_shared; _ask_nas_if_needed ) >/dev/null 2>&1 </dev/null; }
rm -f "$TMP/.nasked"
printf 'EXIST_IS_NAS_CLOUD=false\nEXIST_IS_NAS_OFF=false\nEXIST_NFS_ADDRESS=\n' > "$TMP/.env.shared"
: > "$TMP/.answers"; _nas
assert_eq "no NAS volume enabled → nothing asked" "" "$(cat "$TMP/.nasked" 2>/dev/null)"
sed -i 's/^EXIST_IS_NAS_CLOUD=false$/EXIST_IS_NAS_CLOUD=true/' "$TMP/.env.shared"
( unset EXIST_NFS_ADDRESS; _reload_env_shared; _ask_nas_if_needed ) >/dev/null 2>&1 </dev/null
assert_eq "no terminal → the address stays blank" "EXIST_NFS_ADDRESS=" "$(grep '^EXIST_NFS_ADDRESS=' "$TMP/.env.shared")"
printf '\n' > "$TMP/.answers"; _nas
assert_eq "Enter answers none" "EXIST_NFS_ADDRESS=none" "$(grep '^EXIST_NFS_ADDRESS=' "$TMP/.env.shared")"
assert_eq "...and asks no path" "" "$(grep '^EXIST_NFS_PATH_' "$TMP/.env.shared")"
: > "$TMP/.nasked"; _nas
assert_eq "none is never asked again" "" "$(cat "$TMP/.nasked")"
sed -i 's/^EXIST_NFS_ADDRESS=none$/EXIST_NFS_ADDRESS=/' "$TMP/.env.shared"
printf '10.0.0.5\n/tank/cloud\nlocal\n' > "$TMP/.answers"; : > "$TMP/.nasked"; _nas
assert_eq "an address asks each volume, suggesting /<name> then a sibling of the last path" \
    "EXIST_NFS_ADDRESS [none] EXIST_NFS_PATH_CLOUD_FILES_DATA [/cloud_files_data] EXIST_NFS_PATH_CLOUD_THEMES_DATA [/tank/cloud_themes_data]" \
    "$(xargs < "$TMP/.nasked")"
assert_eq "each answer is appended" "EXIST_NFS_PATH_CLOUD_FILES_DATA=/tank/cloud EXIST_NFS_PATH_CLOUD_THEMES_DATA=local" \
    "$(grep '^EXIST_NFS_PATH_' "$TMP/.env.shared" | xargs)"
assert_contains "with a one-line comment" "# nas/cloud: cloud_files_data on the NAS export" "$(cat "$TMP/.env.shared")"
assert_eq "a db volume is never asked" "" "$(grep '^EXIST_NFS_PATH_CLOUD_SQL' "$TMP/.env.shared")"
sed -i 's/^EXIST_IS_NAS_OFF=false$/EXIST_IS_NAS_OFF=true/' "$TMP/.env.shared"
printf '\n' > "$TMP/.answers"; : > "$TMP/.nasked"; _nas
assert_eq "turning a service on asks only its volumes; Enter takes the suggestion" \
    "EXIST_NFS_PATH_OFF_DATA [/tank/off_data]" "$(xargs < "$TMP/.nasked")"
assert_eq "...which is written" "EXIST_NFS_PATH_OFF_DATA=/tank/off_data" "$(grep '^EXIST_NFS_PATH_OFF' "$TMP/.env.shared")"
rm -rf "$TMP/nas" "$TMP/.nasked" "$TMP/.answers"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
