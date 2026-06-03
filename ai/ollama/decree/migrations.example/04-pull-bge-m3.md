---
routine: ollama-pull
OLLAMA_MODEL: bge-m3:latest
---
Pull bge-m3 (BAAI General Embedding, multilingual). Used by LightRAG as the
embedding model (EMBEDDING_MODEL) for the vector store. Produces 1024-dim
vectors compatible with LightRAG's default EMBEDDING_DIM setting.

WARNING: Do not change the embedding model after first ingestion without
wiping rag_storage — mismatched dimensions corrupt the vector index.
