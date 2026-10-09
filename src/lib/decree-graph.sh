#!/usr/bin/env bash
# decree-graph.sh — regenerate the committed decree graphs.
#
#   ./existential.sh run decree-graph
#
# automation/graph/ and services/automation/backup/graph/ are what `decree graph`
# writes for each project (Mermaid, rendered by GitHub). Run this after changing
# a machine; `./existential.sh test decree` fails while they are stale.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/adhoc.sh
. "${SCRIPT_DIR}/../utils/adhoc.sh"
run_adhoc env WRITE_GRAPH=1 bash /src/test/decree-check.sh
