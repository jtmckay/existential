---
routine: ollama-pull
OLLAMA_ROLE: embed
---
Pull the embedding model — EXIST_MODEL_EMBED. OpenViking uses it for the vector
store; bge-m3 (the default) is multilingual and produces 1024-dim vectors.

EXIST_MODEL_EMBED_DIM in .env.shared must match the model's dimensions — it is
rendered into ai/openviking/.env for you.

WARNING: do not change the embedding model after first ingestion without wiping
volumes/openviking_data. Mismatched dimensions corrupt the vector index.
