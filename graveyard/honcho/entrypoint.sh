#!/usr/bin/env bash
# honcho container entrypoint — runs upstream's documented bootstrap sequence,
# then chains to the image's own entrypoint.
#
# The image's default CMD (`fastapi run`) starts the API against whatever schema
# happens to exist. On a fresh database that is nothing, so honcho's startup
# validator raises "Required vector columns missing" and the container
# restart-loops forever with no hint that a migration was ever needed.
#
# scripts/configure_embeddings.py documents the fix as three steps:
#
#   1. alembic upgrade head            — creates the DEFAULT vector(1536) schema
#   2. configure_embeddings.py         — ALTERs those columns to the target dim
#   3. start the API                   — validators refuse to start on mismatch
#
# The image ships docker/entrypoint.sh, which does 1 and 3 but not 2 — correct
# only for a 1536 model. We embed with EXIST_MODEL_EMBED (bge-m3, 1024), so
# without step 2 honcho swaps one crash-loop for another:
# "public.documents.embedding dim (1536) does not match ... (1024)".
#
# Both steps are idempotent — step 1 is alembic, step 2 no-ops when the schema
# already matches — so this is safe on every start, not just the first.
set -euo pipefail

cd /app

PY=/app/.venv/bin/python

# Step 1. CREATE SCHEMA, CREATE EXTENSION vector, alembic upgrade head.
echo "[honcho-entrypoint] Applying database migrations..."
"$PY" scripts/provision_db.py

# Step 2. Resize the vector columns to [embedding] VECTOR_DIMENSIONS in
# config.toml, which templates.sh renders from EXIST_MODEL_EMBED_DIM.
#
# --yes because there is no TTY here; the interactive prompt would hit EOF.
# This is NOT a blind --force: the script takes an ACCESS EXCLUSIVE lock and
# refuses to alter a column that holds any non-null embedding, so it can never
# silently discard stored vectors. That refusal is the one case worth
# explaining, because it means the embedding model changed under existing data.
if ! "$PY" scripts/configure_embeddings.py --yes; then
    echo "[honcho-entrypoint] ERROR — could not align the pgvector schema with" >&2
    echo "  EXIST_MODEL_EMBED_DIM. If the message above says it refused because" >&2
    echo "  embeddings already exist, the embedding model changed after honcho" >&2
    echo "  stored vectors at the old size. Those vectors cannot be reinterpreted" >&2
    echo "  at a new dimension. Either restore the previous EXIST_MODEL_EMBED /" >&2
    echo "  EXIST_MODEL_EMBED_DIM in .env.shared, or discard the stored memory:" >&2
    echo "    docker compose down honcho honcho-postgres" >&2
    echo "    rm -rf volumes/honcho_postgres_data/pgdata" >&2
    echo "    ./existential.sh && docker compose up -d" >&2
    exit 1
fi

# Step 3. Hand off to the image's own entrypoint rather than repeating its
# server command here — it re-runs step 1 (a no-op now) and then execs the
# API with upstream's arguments, so a pinned-image bump cannot leave us
# starting honcho the wrong way.
exec /app/docker/entrypoint.sh "$@"
