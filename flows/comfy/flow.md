---
name: Images and video on your own card
tagline: ComfyUI workflows a decree message can run, the prompt in its body
docs: /docs/ai/comfyui
services:
  - EXIST_IS_AI_COMFYUI
  - EXIST_IS_SERVICES_AUTOMATION
---

ComfyUI ships with no models: each workflow in automation/lib/comfy/workflows/ names the
files it needs and where they go. Already run ComfyUI elsewhere? Set
EXIST_COMFYUI_URL=http://<host>:8188 and EXIST_IS_AI_COMFYUI=false instead. To run one,
drop a message from flows/comfy/examples/ into volumes/workspace_data/.decree/inbox/, or:
  echo 'a lighthouse at dusk' | docker exec -i automation decree emit --machine comfy --param type=image-text-image
