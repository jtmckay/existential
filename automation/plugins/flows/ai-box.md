---
name: ai-box
x-exist-title: AI box
x-exist-tagline: A GPU box's llama.cpp, ComfyUI and TTS take turns on its one card, through a lease that unloads the others first
x-exist-docs: /docs/hosting/ai-box
x-exist-project: host
needs:
  - ai_box_gpu
---
It runs in the host daemon of the box with the GPU (see the host daemon docs).
In .decree/.env on that box, set AI_BOX_TTS_COMMAND to the command that runs your TTS server,
and AI_BOX_LLAMA_URL and AI_BOX_COMFYUI_URL when they are not on localhost:8080 and :8188.
AI_BOX_SERVICES (default llm,comfy,tts) is what this box offers the other hosts; add strata, with
AI_BOX_STRATA_FAMILY and AI_BOX_STRATA_MODEL, for a Strata the lease starts and stops.
