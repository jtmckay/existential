---
routine: ollama-pull
OLLAMA_ROLE: extract
---
Pull the background extraction model — EXIST_MODEL_EXTRACT. Honcho uses it for
the deriver, dialectic reasoning and session summaries: high-volume background
work where a smaller, faster model beats the chat model.

Defaults to the same tag as EXIST_MODEL_CHAT so only one model stays resident
on a small card, in which case this migration finds it present and skips.
Point it at a separate tag once you have the VRAM for two.
