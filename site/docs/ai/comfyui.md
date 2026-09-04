---
sidebar_position: 6
---

# ComfyUI

- Source: https://github.com/comfyanonymous/ComfyUI
- License: GPL-3.0
- Alternatives: Automatic1111, InvokeAI, Fooocus

Node-based Stable Diffusion UI for local, GPU-accelerated image generation. Workflows are visual graphs that can be exported as JSON and driven programmatically via a REST API — which makes ComfyUI a natural fit for Decree automations.

## Overview

ComfyUI runs at `https://comfyui.EXIST_DOMAIN` (LAN, via Caddy) and `http://comfyui:8188` (Docker internal DNS, for container-to-container calls). It queues and executes image generation jobs via its web UI or HTTP API. No cloud involved — everything runs on the local GPU.

## First Run

After `docker compose up -d`, open `https://comfyui.EXIST_DOMAIN`.

Download a checkpoint model using ComfyUI Manager (accessible from the menu in the top-right). Common starting points:

| Model | Use case |
|---|---|
| `sd_xl_base_1.0.safetensors` | SDXL — general purpose, 1024×1024 native |
| Flux.1-dev | High quality, requires separate text encoder + VAE |

The container's whole working tree is the `comfyui_data` volume: the image copies ComfyUI out to `/root` on first boot, so models, custom nodes,
generated images and saved workflows are all one mount. On the host that is `volumes/comfyui_data/ComfyUI/` — checkpoints in
`models/checkpoints/` (`models/diffusion_models`, `models/text_encoders`, `models/vae`, `models/loras` for the rest), generated images in
`output/`, saved workflows and settings in `user/`.

:::warning No authentication
ComfyUI has no login of its own, and nothing is put in front of it. Anyone who can reach
`https://comfyui.EXIST_DOMAIN` can queue workflows, read and write files under the volume, and install custom nodes — which is arbitrary Python
executed in the container. Keep it on the tailnet; do not put it behind a public A record.
:::

## API

ComfyUI exposes a REST API on port 8188.

| Endpoint | Method | Purpose |
|---|---|---|
| `/prompt` | POST | Queue a workflow for generation |
| `/history/{prompt_id}` | GET | Poll generation status; includes output filenames when done |
| `/view` | GET | Download a generated image (`?filename=<f>&type=output`) |
| `/system_stats` | GET | GPU memory usage and system info |

The `/prompt` body is a workflow exported from the ComfyUI UI as JSON, wrapped in a small envelope:

```json
{
  "prompt": { ...workflow nodes... },
  "client_id": "any-string-to-group-your-requests"
}
```

## Using ComfyUI from Decree

Decree routines are shell scripts in `automation/shared_routines/`. They call ComfyUI's HTTP API using `curl`. The pattern is: POST a workflow, poll `/history` until the job finishes, then retrieve the output filename.

### The routines that ship

Three are already written, registered in `services/automation/decree/config.exist.yml` and off by default:

| Routine | Workflow | Needs |
|---|---|---|
| `comfy-image-text` | `automation/lib/comfy/image_flux2_text_landscape.json` | Flux2-dev |
| `comfy-image-text-image` | `automation/lib/comfy/image_flux2_text_image.json` | Flux2-dev, plus a reference image |
| `comfy-video-i2v` | `automation/lib/comfy/video_i2v_wan2.2_14B_long.json` | Wan 2.2 I2V 14B |

Each workflow JSON carries the HuggingFace URL for every model it loads, so the download list is the file itself. Flip a routine's `enabled: true`, restart automation, then:

```bash
docker exec automation decree run comfy-image-text
```

Write your own the same way: POST the workflow to `/api/prompt`, poll `/history/{id}` until `outputs` appears, then fetch the file from `/view`.

## Telegram → ComfyUI Workflow

A common pattern: a Telegram message triggers image generation and the result comes back as a photo in the chat.

```
User sends: /imagine a sunset over mountains
        │
        ▼
telegram-poll picks up the message
        │
        ▼
Extracts the prompt, calls comfyui-generate
        │
        ▼
comfyui-generate POSTs workflow to comfyui:8188/prompt
        │
        ▼
Polls /history/{id} until "outputs" appears
        │
        ▼
Downloads image via /view?filename=...&type=output
        │
        ▼
Sends image back to the Telegram chat via Bot API
```

The `telegram-poll` routine in `automation/shared_routines/telegram-poll.sh` handles inbound messages. Wire ComfyUI into it by checking the message body for a command prefix (e.g. `/imagine`) and dispatching to `comfyui-generate`.

See [Telegram integration](../integrations/telegram) for bot credentials setup.

## Designing Workflows

The recommended workflow authoring loop:

1. Open `https://comfyui.EXIST_DOMAIN` and build the workflow visually
2. Click **Save (API format)** — this exports the node graph as the flat JSON that `/prompt` accepts (distinct from the regular save format, which includes UI layout metadata)
3. Paste the exported JSON into your routine as the `WORKFLOW` heredoc
4. Replace hardcoded values (prompt text, seed, dimensions) with variables the routine controls

Use a random seed rather than a fixed `42` to get different images each run:

```bash
SEED=$(od -A n -t u4 -N 4 /dev/urandom | tr -d ' ')
```

## Tips

- **Monitor GPU**: `curl -s http://comfyui:8188/system_stats | jq .`
- **Batch generation**: submit multiple `/prompt` requests — ComfyUI queues them and processes in order, each with its own `prompt_id`
- **Model persistence**: the `comfyui_data` volume keeps all downloaded models across `docker compose down`
- **Workflow iteration**: small changes to steps (20→30), CFG scale (7→9), or sampler (`euler` → `dpmpp_2m`) have meaningful quality impact — iterate in the UI before committing to a routine
- **Image retrieval**: `SaveImage` nodes write to `/root/ComfyUI/output/` inside the container; the `/view` endpoint serves them from there with no additional volume mount needed

## Debugging

```bash
docker compose logs comfyui
curl -s http://comfyui:8188/system_stats | jq .
```
