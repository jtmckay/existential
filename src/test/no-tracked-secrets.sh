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
secret_re='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{30,}'
if matches="$(git grep -nIE "$secret_re" -- . ':(exclude)graveyard/*' 2>/dev/null)"; then
    if [ -n "$matches" ]; then
        flag "API-key-shaped string in tracked content:"
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
