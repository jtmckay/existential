---
routine: ollama-pull
OLLAMA_MODEL: qwen2.5:7b
---
Pull qwen2.5:7b. Used by LightRAG for entity and relationship extraction
during document ingestion (LLM_MODEL). A smaller, instruction-following
model optimised for structured extraction — faster and cheaper than gemma4
for this high-volume role.
