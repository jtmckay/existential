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

# existential.sh exports .env.shared before running initials; source it anyway so
# `./existential.sh run openviking` works on its own. EXIST_OLLAMA_URL is the one
# place the ollama address is named — old installs predate the key.
if [[ -f "${REPO_ROOT}/.env.shared" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env.shared"
    set +a
fi
OLLAMA_URL="${EXIST_OLLAMA_URL:-http://ollama:11434}"

# ── Knowledgebase directory ───────────────────────────────────────────────────
# viking/ at the repo root is the user's own knowledgebase: whatever they drop in
# there gets indexed. It is a plain host directory, not a declared volume —
# human-facing content, like workspace/, so it stays out of volumes/.
#
# generate-compose.ts already creates it (ensureBindSource) on a full run, but
# `./existential.sh run openviking` skips that, so create it here too. The README
# is seeded only when absent — this is the user's directory, not ours.
VIKING_DIR="${REPO_ROOT}/viking"
mkdir -p "${VIKING_DIR}"
if [[ ! -e "${VIKING_DIR}/README.md" ]]; then
    cat > "${VIKING_DIR}/README.md" << 'VIKINGEOF'
# viking/ — your knowledgebase

Drop anything you want OpenViking to index in here: notes, docs, transcripts,
exported wikis. Subdirectories are preserved, so organise it however you like.

OpenViking mounts this read-only at `/app/viking` and re-scans it every 300
seconds — no restart needed after you add or edit a file. Hermes reaches the
index through the openviking MCP server, so anything in here is searchable by
the agent.

This directory is gitignored: it is yours, and it never lands in a commit.
Delete this README once you have your bearings — nothing regenerates it while
it exists, and nothing depends on it.

Not this directory:

- `volumes/openviking_notes_data` — synced from your rclone remote by the
  `openviking-sync` routine. Rclone is the source of truth; edits here are
  overwritten.
- `volumes/openviking_resources_data` — content scraped by hermes/firecrawl.
VIKINGEOF
    echo "[openviking] viking/ knowledgebase directory created."
fi

DATA_DIR="${REPO_ROOT}/volumes/openviking_data"
mkdir -p "${DATA_DIR}"

CONF="${DATA_DIR}/ov.conf"
if [[ -f "${CONF}" ]]; then
    # ov.conf is the user's once written — except for the embedding endpoint,
    # which is EXIST_OLLAMA_URL's to own. Without this, moving ollama to another
    # host leaves openviking retrying a dead address, and the only symptom is
    # "Failed to generate embedding: Connection error" deep in its logs.
    have_base=$(grep -m1 '"api_base"' "${CONF}" \
        | sed -E 's/.*"api_base"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)
    if [[ "${have_base}" == "${OLLAMA_URL}/v1" ]]; then
        echo "[openviking] ov.conf exists — skipping (delete to regenerate)."
    elif [[ "${have_base}" =~ ^https?://[^/]+:11434(/v1)?$ ]]; then
        echo "[openviking] ov.conf api_base=${have_base} but EXIST_OLLAMA_URL=${OLLAMA_URL} — reconciling."
        sed -i -E "s#\"api_base\"[[:space:]]*:[[:space:]]*\"[^\"]*\"#\"api_base\": \"${OLLAMA_URL}/v1\"#" "${CONF}"
    else
        echo "[openviking] ov.conf api_base=${have_base} (not an ollama endpoint) — leaving it alone."
    fi
    exit 0
fi

cat > "${CONF}" << EOF
{
  "embedding": {
    "dense": {
      "provider": "ollama",
      "api_key": "local",
      "api_base": "${OLLAMA_URL}/v1",
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
