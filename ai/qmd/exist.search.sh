#!/usr/bin/env bash
# qmd — search the workspace from the host, without MCP.
#
#   ./existential.sh run qmd search <the words you remember>
#
# qmd publishes no port, so this runs in existential-adhoc, which is on the
# exist network. code-server's terminal has the same command as `search`.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/utils/adhoc.sh"
adhoc_self_elevate "${BASH_SOURCE[0]}" "$@"

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/automation/lib/recall/search.sh" "$@"
