#!/usr/bin/env bash
# no-tracked-secrets.sh — assert this PUBLIC repo tracks no rendered secrets.
#
# Runs on the HOST (needs git, which the adhoc image does not ship). Wired into
# `./existential.sh test` alongside the host-side container-health gate. This is
# the standing backstop to the .githooks/pre-commit guard (audit H-3): even if a
# commit bypassed the hook, this fails loudly so the leak is caught before push.
#
# Read-only: it only inspects `git ls-files` / blob contents, never writes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  PASS  no-tracked-secrets (not a git repo — skipped)"
    exit 0
fi

fail=0
flag() { echo "  FAIL  $*" >&2; fail=1; }

# ── Rendered secret paths that must never be tracked ──────────────────────────
# (the .env.exist* / .pem.example templates ARE meant to be tracked)
while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="${f##*/}"
    case "$base" in
        .env|.env.shared|.env.local|.env.generated|cloudflare-key.pem|cloudflare.pem|internal-key.pem|internal-ca-key.pem|*_password.txt)
            flag "tracked rendered secret: $f" ;;
    esac
    case "$f" in
        */secrets/*) [ "$base" = ".gitkeep" ] || flag "tracked file under secrets/: $f" ;;
    esac
done < <(git ls-files)

# ── Secret-shaped content in any tracked file (excl. graveyard + placeholders) ─
# Known vendor token shapes (high-signal prefixes) + JWTs. SEC-03: broadened beyond
# the original AWS/GitHub/Slack/OpenAI/Google set to cover more GitHub token kinds
# (gho_/ghs_/ghr_/ghu_, github_pat_), Slack app tokens (xapp-), Stripe (sk_/rk_live|test),
# npm tokens, and JSON Web Tokens (eyJ…​.eyJ…​.…).
secret_re='AKIA[0-9A-Z]{16}|gh[opsru]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|xapp-[0-9]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|(sk|rk)_(live|test)_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|npm_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_=-]{8,}\.eyJ[A-Za-z0-9_=-]{8,}\.[A-Za-z0-9_=-]{8,}'
if matches="$(git grep -nIE "$secret_re" -- . ':(exclude)graveyard/*' 2>/dev/null)"; then
    if [ -n "$matches" ]; then
        flag "API-key-shaped string in tracked content:"
        echo "$matches" >&2
    fi
fi

# ── Generic keyword-anchored secret assignments (SEC-03) ──────────────────────
# Catches DB passwords / bearer tokens / client secrets that match no vendor prefix:
# a secret-ish key, then a quoted value ≥20 chars. Placeholder templates
# (*.exist.* / *.example) are exempt — they legitimately hold EXIST_* placeholders
# in exactly this shape (same exemption the private-key check uses).
assign_re='(secret|token|passwd|password|api[_-]?key|access[_-]?key|client[_-]?secret|bearer)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/_-]{20,}["'"'"']'
if matches="$(git grep -nIiE "$assign_re" -- . ':(exclude)graveyard/*' ':(exclude)*.exist.*' ':(exclude)*.example' 2>/dev/null)"; then
    if [ -n "$matches" ]; then
        flag "high-entropy secret-shaped assignment in tracked content:"
        echo "$matches" >&2
    fi
fi

# Private-key material in non-placeholder tracked files.
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"
    case "$file" in
        *.exist.*|*.example|graveyard/*) continue ;;
    esac
    flag "private key material in tracked file: $hit"
done < <(git grep -nIE -- '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' 2>/dev/null || true)

if [ "$fail" -ne 0 ]; then
    echo "" >&2
    echo "  This repo is public — the above must be removed from the index AND history." >&2
    exit 1
fi
echo "  PASS  no-tracked-secrets"
exit 0
