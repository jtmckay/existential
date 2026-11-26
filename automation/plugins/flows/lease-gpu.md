---
name: lease-gpu
x-exist-title: Lease GPU
x-exist-tagline: This box shares its one GPU with the fleet, where llama.cpp, Strata, ComfyUI and TTS take turns through a lease that unloads the others first
x-exist-docs: /docs/hosting/ai-box
x-exist-project: host
needs:
  - lease_gpu
  - decree_prune   # the host's runs, pruned like every project's (clean-runs is not the host's)
---
It runs in the host daemon of the box with the GPU (see the host daemon docs).
In .decree/.env on that box, set AI_BOX_TTS_COMMAND to the command that runs your TTS server,
and AI_BOX_LLAMA_URL and AI_BOX_COMFYUI_URL when they are not on localhost:8080 and :8188.
AI_BOX_SERVICES (default llm,comfy,tts) is what this box offers the other hosts; add strata, with
AI_BOX_STRATA_FAMILY and AI_BOX_STRATA_MODEL, for a Strata the lease starts and stops.
