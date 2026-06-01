---
sidebar_position: 6
---

# ComfyUI

- Source: https://github.com/comfyanonymous/ComfyUI
- License: GPL-3.0
- Alternatives: Automatic1111, InvokeAI, Fooocus

Node-based Stable Diffusion UI for local, GPU-accelerated image generation. Workflows are visual graphs that can be exported as JSON and driven programmatically via a REST API — which makes ComfyUI a natural fit for Decree automations.

## Overview

ComfyUI runs at `https://comfyui.internal` (LAN, via Caddy) and `http://comfyui:8188` (Docker internal DNS, for container-to-container calls). It queues and executes image generation jobs via its web UI or HTTP API. No cloud involved — everything runs on the local GPU.

## First Run

After `docker compose up -d`, open `https://comfyui.internal`.

Download a checkpoint model using ComfyUI Manager (accessible from the menu in the top-right). Common starting points:

| Model | Use case |
|---|---|
| `sd_xl_base_1.0.safetensors` | SDXL — general purpose, 1024×1024 native |
| Flux.1-dev | High quality, requires separate text encoder + VAE |

Models are stored in the `comfyui_data` volume at `/workspace/ComfyUI/models/checkpoints/` and persist across container restarts.

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

Decree routines are shell scripts in `automations/shared_routines/`. They call ComfyUI's HTTP API using `curl`. The pattern is: POST a workflow, poll `/history` until the job finishes, then retrieve the output filename.

### Example routine

```bash
#!/usr/bin/env bash
# automations/shared_routines/comfyui-generate.sh
set -euo pipefail

COMFYUI_URL="${COMFYUI_URL:-http://comfyui:8188}"
CLIENT_ID="$(uuidgen)"
USER_PROMPT="${DECREE_PROMPT:-a scenic mountain landscape}"

# Build workflow JSON — export this from the ComfyUI UI (Save > API format), then paste here
WORKFLOW=$(cat <<'EOF'
{
  "3": {"class_type": "KSampler",              "inputs": {"seed": 42, "steps": 20, "cfg": 7, "sampler_name": "euler", "scheduler": "normal", "denoise": 1, "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
  "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
  "5": {"class_type": "EmptyLatentImage",       "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
  "6": {"class_type": "CLIPTextEncode",         "inputs": {"text": "PROMPT_HERE", "clip": ["4", 1]}},
  "7": {"class_type": "CLIPTextEncode",         "inputs": {"text": "ugly, blurry, low quality", "clip": ["4", 1]}},
  "8": {"class_type": "VAEDecode",              "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
  "9": {"class_type": "SaveImage",              "inputs": {"filename_prefix": "decree", "images": ["8", 0]}}
}
EOF
)

# Inject the prompt text
PROMPT=$(echo "$WORKFLOW" | sed "s/PROMPT_HERE/${USER_PROMPT}/g")

# Submit the job
RESPONSE=$(curl -sS -X POST "${COMFYUI_URL}/prompt" \
    -H "Content-Type: application/json" \
    -d "{\"prompt\": ${PROMPT}, \"client_id\": \"${CLIENT_ID}\"}")
PROMPT_ID=$(echo "$RESPONSE" | grep -o '"prompt_id":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$PROMPT_ID" ]]; then
    echo "ERROR: ComfyUI rejected the job. Response: $RESPONSE" >&2
    exit 1
fi

echo "Queued: $PROMPT_ID"

# Poll until the job finishes (up to 5 minutes)
for i in $(seq 1 60); do
    STATUS=$(curl -sS "${COMFYUI_URL}/history/${PROMPT_ID}")
    if echo "$STATUS" | grep -q '"outputs"'; then
        FILENAME=$(echo "$STATUS" | grep -o '"filename":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "Generated: ${COMFYUI_URL}/view?filename=${FILENAME}&type=output"
        exit 0
    fi
    sleep 5
done

echo "ERROR: timed out waiting for $PROMPT_ID" >&2
exit 1
```

Register it in `services/decree/decree/config.exist.yml`:

```yaml
shared_routines:
  comfyui-generate:
    enabled: true
```

Trigger it manually:

```bash
docker exec decree decree run comfyui-generate
```

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

The `telegram-poll` routine in `automations/shared_routines/telegram-poll.sh` handles inbound messages. Wire ComfyUI into it by checking the message body for a command prefix (e.g. `/imagine`) and dispatching to `comfyui-generate`.

See [Telegram integration](../integrations/telegram) for bot credentials setup.

## Designing Workflows

The recommended workflow authoring loop:

1. Open `https://comfyui.internal` and build the workflow visually
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
- **Image retrieval**: `SaveImage` nodes write to `/workspace/ComfyUI/output/` inside the container; the `/view` endpoint serves them from there with no additional volume mount needed

## Debugging

```bash
docker compose logs comfyui
curl -s http://comfyui:8188/system_stats | jq .
```
