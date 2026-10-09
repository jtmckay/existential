#!/usr/bin/env bash
# routines_snapshot — copy decree's own description of this project into
# workspace/ai/decree/, which is how hermes (no mount into automation/) learns
# what decree can run and how to ask for it:
#
#   system.md     every machine, its description and what it emits (decree graph)
#   machines/     each machine's data: the params it takes, with defaults
#   endpoints.yml automation-webhook's endpoints, the /hermes/* ones hermes may call
set -euo pipefail

out="${AGENT_OUTPUT_DIR:-/workspace/ai}/decree"
mkdir -p "${out}/machines"
cp .decree/graph/system.md "${out}/"
rm -f "${out}"/machines/*.yml
cp .decree/machines/*.yml "${out}/machines/"
cp .decree/decree-go-rest.yml "${out}/endpoints.yml"
# decree 0.4's single-file snapshot, superseded by the directory above.
rm -f "${AGENT_OUTPUT_DIR:-/workspace/ai}/decree-routines.md"
echo "Wrote ${out}"
