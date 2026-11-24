---
name: image-ocr
x-exist-project: automation
x-exist-title: Photograph it, and the text is yours
x-exist-tagline: An image synced to Nextcloud gets its text written beside it by a vision model
x-exist-docs: /docs/flows/image-ocr
needs:
  - ocr
  - nextcloud-capture
---

It uses EXIST_MODEL_VISION at its endpoint. With a local ollama, the local-models flow
pulls it.
