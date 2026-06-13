#!/usr/bin/env bash
# openviking — pre-startup init: write ov.conf into the data volume.
#
# Runs on the host (needs no container tooling). Called every `./existential.sh run`;
# skips silently if ov.conf already exists — delete it to regenerate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

# shellcheck source=.env
source "${SCRIPT_DIR}/.env"

DATA_DIR="${REPO_ROOT}/volumes_local/openviking_data"
mkdir -p "${DATA_DIR}"

CONF="${DATA_DIR}/ov.conf"
if [[ -f "${CONF}" ]]; then
    echo "[openviking] ov.conf exists — skipping (delete to regenerate)."
    exit 0
fi

cat > "${CONF}" << EOF
{
  "embedding": {
    "dense": {
      "provider": "ollama",
      "api_key": "local",
      "api_base": "http://ollama:11434/v1",
      "model": "${OPENVIKING_EMBEDDING_MODEL}",
      "dimension": ${OPENVIKING_EMBEDDING_DIM}
    }
  },
  "storage": {
    "workspace": "/app/.openviking/data"
  },
  "server": {
    "host": "0.0.0.0",
    "port": 1933,
    "auth_mode": "api_key",
    "root_api_key": "${OPENVIKING_API_KEY}",
    "cors_origins": ["*"]
  },
  "memory": {
    "version": "v2"
  }
}
EOF

echo "[openviking] ov.conf written."
