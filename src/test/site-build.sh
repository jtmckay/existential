#!/usr/bin/env bash
# site-build.sh — build the docs site (site/) the way Cloudflare does: `npm run build`.
#
# MDX is stricter than Markdown (`{` starts an expression), and docusaurus.config.ts throws
# on a broken link, so a docs change can fail the deploy that no other gate reads.
# Builds in site/Dockerfile's image, whose `npm ci` layer is cached; the source is
# copied in, so nothing is written to the checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../utils/adhoc.sh
. "${ROOT}/src/utils/adhoc.sh"
if ! adhoc_find_runtime; then
    echo "  site-build: no docker or podman: skipped; CI runs it"
    exit 0
fi

echo "  building the docs site (site/)"; log="$(mktemp)"
$DOCKER_CMD build -q -t existential-site "${ROOT}/site" >/dev/null
if $DOCKER_CMD run --rm -v "${ROOT}/site":/site:ro,z existential-site sh -c \
    'tar -C /site --exclude=./node_modules --exclude=./build --exclude=./.docusaurus -cf - . | tar -xf - && npm run build' \
    >"$log" 2>&1; then
    rm -f "$log"
    echo "  PASS  site-build"
else
    grep -v '^\s*$' "$log" | tail -40 >&2; rm -f "$log"
    echo "  FAIL  site-build: npm run build failed (above)" >&2
    exit 1
fi
