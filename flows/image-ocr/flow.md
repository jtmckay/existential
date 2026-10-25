---
name: Photograph it, and the text is yours
tagline: An image synced to Nextcloud gets its text written beside it by a vision model
docs: /docs/flows/image-ocr
flows:
  - nextcloud-capture
processors:
  - ollama-ocr.sh
---

It uses EXIST_MODEL_VISION at its endpoint. With a local ollama, the local-models flow
pulls it.
