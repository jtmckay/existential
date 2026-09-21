---
name: ComfyUI Image Generation
tagline: Node-graph image and video generation on your own card, driven by hand or by a routine
e2e: false
e2e_skip: Needs multi-GB model checkpoints downloaded from HuggingFace/civitai
services:
  - var: EXIST_IS_AI_COMFYUI
    label: ComfyUI
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (for the comfy routine)
---

ComfyUI ships with **no models**. The container starting is not the same as it
working — the download is the quest.

── Already have one elsewhere? ───────────────────────────────────────────

Point the stack at it instead of running a second copy. One line in
`.env.shared`, then re-run `./existential.sh`:

       EXIST_COMFYUI_URL=http://bigbox:8188
       EXIST_IS_AI_COMFYUI=false

The comfy routine, https://comfyui.${EXIST_DOMAIN} and the comfyui test all
follow that address. The rest of this quest is then that machine's business.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_AI_COMFYUI=true
       ./existential.sh
       docker compose up -d

It answers at https://comfyui.${EXIST_DOMAIN}.

── 2. Get a checkpoint ───────────────────────────────────────────────────

Use the ComfyUI Manager node inside the UI, or drop `.safetensors` files
straight into:

       volumes/comfyui_data/ComfyUI/models/checkpoints/

A good first one is SDXL base — 6.9 GB, from civitai.com or HuggingFace.

── 3. The routine's models are different ─────────────────────────────────

The `comfy` routine picks a workflow with `type:` — each is a .yml/.json pair
in `automation/lib/comfy/workflows/`, and the popular ones (image-text-image,
video-i2v) want Flux2 and Wan 2.2, not SDXL. Each binding's header names its
own HuggingFace URLs; the files go under:

       volumes/comfyui_data/ComfyUI/models/diffusion_models/
                                          /text_encoders/
                                          /vae/
                                          /loras/

Enable the routine in `services/automation/decree/config.yml`:

       comfy: { enabled: true }

Then trigger one by hand — the **message body is the prompt**, and running with
an unknown `type` lists the ones you have:

       printf -- '---\nroutine: comfy\ntype: image-text-image\noutput_prefix: test\n---\na lighthouse at dusk\n' \
         > automation/inbox/comfy.md

Adding a flow is adding a .json and a .yml in that directory; the routine needs
no change.

── 4. Check it ───────────────────────────────────────────────────────────

       ./existential.sh test comfyui

It checks that ComfyUI answers and that /object_info carries every node class
the shipped workflows use — a missing custom node is the other way a graph
fails after the container looked healthy.
