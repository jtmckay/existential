#!/usr/bin/env bash
# decree-graph.sh — regenerate the committed decree graphs.
#
#   ./existential.sh run decree-graph
#
# automation/graph/ and services/automation/backup/graph/ are what `decree graph`
# writes for each project (Mermaid, rendered by GitHub). Run this after changing
# a machine; `./existential.sh test decree` fails while they are stale.
# existential.sh runs it inside adhoc, where decree is on PATH.
set -euo pipefail
WRITE_GRAPH=1 exec bash "$(dirname "${BASH_SOURCE[0]}")/../test/decree-check.sh"
