---
routine: ollama-pull
OLLAMA_ROLE: vision
---
Pull the vision model — EXIST_MODEL_VISION. Used by the ollama-ocr file
processor (automation/lib/file-processors.example/ollama-ocr.sh) for text
extraction from images sent via Telegram or dropped into Nextcloud, and
available in Open WebUI for image chat.

EXIST_MODEL_VISION defaults to the SAME tag as EXIST_MODEL_CHAT: every tier
model is multimodal, so an image reuses the model already resident instead of
evicting it for a separate llava. This migration then finds it present and
skips. Set it blank to turn image handling off entirely.
