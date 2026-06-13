---
routine: ollama-pull
OLLAMA_MODEL: bge-m3:latest
---
Pull bge-m3 (BAAI General Embedding, multilingual). Used by OpenViking as the
embedding model for the vector store. Produces 1024-dim vectors; set
OPENVIKING_EMBEDDING_DIM=1024 in ai/openviking/.env to match.

WARNING: Do not change the embedding model after first ingestion without
wiping openviking_data — mismatched dimensions corrupt the vector index.
