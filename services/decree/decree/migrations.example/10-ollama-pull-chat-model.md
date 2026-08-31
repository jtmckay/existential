---
routine: ollama-pull
OLLAMA_ROLE: chat
---
Pull the primary chat/reasoning model — whatever EXIST_MODEL_CHAT names in
.env.shared. Used by Hermes and Open WebUI.

The tag is NOT hardcoded here: the decree container receives the
EXIST_MODEL_* globals and the ollama-pull routine resolves
the role against them. Change the model in one place — the "Model Selection"
block in .env.shared — and re-run this migration.

Expect a few minutes on first pull — 4.3 GB at the 8 GB default tier. The tier
table (src/utils/model-tiers.sh) sizes this so chat and embeddings both stay
resident on the card you told quest you have.
