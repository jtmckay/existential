#!/usr/bin/env bash
# guard-selftest.sh — prove the secret guards actually TRIP.
#
# The audit's H-3 guards (.githooks/pre-commit + src/test/no-tracked-secrets.sh)
# normally only ever run against a clean tree, so a working guard and a *broken*
# guard look identical — both "pass". That is exactly how the pre-commit grep
# bug hid (it errored on every run yet let the commit through). A control with
# no negative test is a comment, not a control.
#
# This is that negative test: it plants known-bad, secret-SHAPED fixtures in
# throwaway git repos and asserts each guard exits non-zero — and that it still
# ALLOWS clean input and the *.exist.* / *.example placeholder exemptions. If a
# future edit silently disarms a guard, this goes red.
#
# Host-side (needs git, which the adhoc image lacks) — same reason
# no-tracked-secrets.sh lives here rather than under unit/. Read-only w.r.t. the
# real repo: all writes happen in mktemp dirs that are cleaned on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.githooks/pre-commit"
SCANNER="$ROOT/src/test/no-tracked-secrets.sh"

if ! command -v git >/dev/null 2>&1; then
    echo "  PASS  guard-selftest (no git — skipped)"
    exit 0
fi

fail=0
pass()  { echo "  PASS  $*"; }
flunk() { echo "  FAIL  $*" >&2; fail=1; }

# ── Fixture secrets — fake but correctly SHAPED ───────────────────────────────
# Built by concatenating adjacent string literals so the *source bytes of this
# tracked file* never contain a matchable pattern (otherwise the very scanner
# under test would flag this file). At runtime the quotes vanish and the
# variables hold the real shapes, which we write only into throwaway /tmp repos.
FAKE_PEM_BEGIN="-----BEGIN RSA PRIVATE ""KEY-----"
FAKE_PEM_END="-----END RSA PRIVATE ""KEY-----"
FAKE_PEM="$(printf '%s\nMIIBfakefakefakefakefakefakefakefake\n%s\n' "$FAKE_PEM_BEGIN" "$FAKE_PEM_END")"
FAKE_AWS="AKIA""IOSFODNN7EXAMPLE"   # canonical AWS docs example key (AKIA + 16)
# A decree-webhook bearer secret is a bare UUID or hex string. It deliberately
# matches NONE of the content patterns the scanners use, so these fixtures
# prove the filename rule is what catches it — the content rules cannot.
FAKE_WEBHOOK_SECRET="3f7a1c88-9b2e-4d61-8a05-1e9c4b7d2f60"

TMPS=()
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

# Prints a fresh git repo dir. The caller (running in the main shell, unlike a
# $(...) subshell) is responsible for appending it to TMPS so cleanup sees it.
newrepo() {
    local d; d="$(mktemp -d)"
    git -C "$d" init -q
    git -C "$d" config user.email selftest@local
    git -C "$d" config user.name  selftest
    echo "$d"
}

# ── pre-commit hook: stage one fixture, return the hook's exit code in RC ──────
RC=0
# $3 (optional) drops a sibling *.exist.* template beside the fixture. The
# config-file guards key off "was this rendered from a template?", so proving
# both sides of that needs a fixture that can carry one.
hook_rc() {                        # $1=relpath  $2=content  [$3=template relpath]
    local rel="$1" content="$2" tmpl="${3:-}" d rc=0
    d="$(newrepo)"; TMPS+=("$d")
    mkdir -p "$d/$(dirname "$rel")"
    printf '%s\n' "$content" > "$d/$rel"
    [ -n "$tmpl" ] && printf 'secret: EXIST_32_CHAR_HEX_KEY\n' > "$d/$tmpl"
    git -C "$d" add -fA            # -f: simulate the `git add -f` bypass the hook defends against
    ( cd "$d" && bash "$HOOK" ) >/dev/null 2>&1 || rc=$?
    RC=$rc
}

# ── no-tracked-secrets.sh: commit one fixture, return scanner exit code in RC ──
scanner_rc() {                     # $1=relpath  $2=content  [$3=template relpath]
    local rel="$1" content="$2" tmpl="${3:-}" d rc=0
    d="$(newrepo)"; TMPS+=("$d")
    mkdir -p "$d/src/test" "$d/$(dirname "$rel")"
    cp "$SCANNER" "$d/src/test/no-tracked-secrets.sh"   # scanner pins ROOT to ../.. of its own path
    printf '%s\n' "$content" > "$d/$rel"
    [ -n "$tmpl" ] && printf 'secret: EXIST_32_CHAR_HEX_KEY\n' > "$d/$tmpl"
    git -C "$d" add -fA
    git -C "$d" commit -qm fixture
    bash "$d/src/test/no-tracked-secrets.sh" >/dev/null 2>&1 || rc=$?
    RC=$rc
}

# expect $1 = block|allow given the actual code in RC
check() {                          # $1=label  $2=block|allow
    if [ "$2" = block ] && [ "$RC" -ne 0 ]; then pass "$1 → blocked"
    elif [ "$2" = allow ] && [ "$RC" -eq 0 ]; then pass "$1 → allowed"
    else flunk "$1: expected $2, but guard exit=$RC"; fi
}

echo "[guard-selftest] pre-commit hook"
hook_rc "server.pem"                  "$FAKE_PEM"; check "private key in server.pem"        block
hook_rc "cloudflare-key.exist.pem"    "$FAKE_PEM"; check "private key in *.exist.pem (placeholder)" allow
hook_rc "deploy.example"              "$FAKE_PEM"; check "private key in *.example (placeholder)"    allow
hook_rc "config.yml"                  "key=$FAKE_AWS"; check "AWS key in config.yml"        block
hook_rc "services/automation/webhook/config.yml" "secret: $FAKE_WEBHOOK_SECRET" "services/automation/webhook/config.exist.yml"
check "rendered webhook config.yml (content matches no pattern)"                             block
hook_rc "services/automation/webhook/config.exist.yml" "secret: EXIST_32_CHAR_HEX_KEY"
check "webhook config.exist.yml template"                                                    allow
hook_rc "hosting/loki/loki-config.yaml" "server: {http_listen_port: 3100}"
check "upstream *-config.yaml (no *.exist.* template) still committable"                     allow
hook_rc "ai/chatterbox/config.yaml" "secret: $FAKE_WEBHOOK_SECRET" "ai/chatterbox/config.exist.yaml"
check "rendered *-config.yaml (has a template) blocked like its .yml twin"                    block
hook_rc ".env"                        "X=1";       check "rendered .env staged"             block
hook_rc "ai/foo/secrets/token"        "abc";       check "file under secrets/ staged"       block
hook_rc "ai/foo/secrets/.gitkeep"     "";          check "secrets/.gitkeep staged"          allow
hook_rc "README.md"                   "# hello";   check "clean README"                     allow

echo "[guard-selftest] no-tracked-secrets.sh"
scanner_rc "server.pem"               "$FAKE_PEM"; check "tracked private key in server.pem"      block
scanner_rc "cloudflare-key.exist.pem" "$FAKE_PEM"; check "tracked private key in *.exist.pem"      allow
scanner_rc "cloudflare-key.pem.example" "$FAKE_PEM"; check "tracked private key in *.example"       allow
scanner_rc "notes.txt"                "k=$FAKE_AWS"; check "tracked AWS-shaped key"                block
scanner_rc ".env"                     "X=1";       check "tracked rendered .env"                   block
scanner_rc "services/automation/webhook/config.yml" "secret: $FAKE_WEBHOOK_SECRET" "services/automation/webhook/config.exist.yml"
check "tracked rendered webhook config.yml"                                                        block
scanner_rc "services/automation/webhook/config.exist.yml" "secret: EXIST_32_CHAR_HEX_KEY"
check "tracked webhook config.exist.yml template"                                                  allow
scanner_rc "hosting/loki/loki-config.yaml" "server: {http_listen_port: 3100}"
check "tracked upstream *-config.yaml (no template)"                                               allow
scanner_rc "ai/chatterbox/config.yaml" "secret: $FAKE_WEBHOOK_SECRET" "ai/chatterbox/config.exist.yaml"
check "tracked rendered *-config.yaml (has a template)"                                            block
scanner_rc "ai/foo/secrets/cred"      "abc";       check "tracked file under secrets/"             block
scanner_rc "README.md"                "# hello";   check "clean tracked repo"                      allow

echo ""
if [ "$fail" -ne 0 ]; then
    echo "  A secret guard did NOT behave as expected — it may be silently disarmed." >&2
    echo "  (This is the failure mode that hid the pre-commit grep bug.)" >&2
    exit 1
fi
echo "  PASS  guard-selftest (both secret guards trip on planted secrets)"
exit 0
