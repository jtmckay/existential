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

## Using a ComfyUI you already run

The GPU does not have to be in this machine. `EXIST_COMFYUI_URL` in `.env.shared` is the one
address the stack uses — the `comfy` routine POSTs there, `comfyui.EXIST_DOMAIN` proxies there,
and `exist.test.sh` checks it — so pointing it elsewhere and turning the local container off is
the whole job:

```bash
EXIST_COMFYUI_URL=http://bigbox:8188
EXIST_IS_AI_COMFYUI=false
```

Then `./existential.sh && docker compose up -d`. Everything below about models, volumes and
workflows is then that machine's business, not this one's — the workflows still live here, in
`automation/lib/comfy/workflows/`, but the checkpoints they name must exist over there.

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

### The routine that ships

One routine, `comfy`, is already written and registered in
`services/automation/decree/config.exist.yml` (off by default). Its `type` parameter names a
workflow in `automation/lib/comfy/workflows/`:

| `type` | Model | Needs |
|---|---|---|
| `image-text` | Flux2-dev | — |
| `image-text-image` | Flux2-dev | `input_image` |
| `image-qwen-angles` | Qwen-Image-Edit 2511 | `input_image`, and a list of items (below) |
| `video-i2v` | Wan 2.2 I2V 14B | `input_image` |
| `video-ltx-text` | LTX-2.5 | — |
| `video-ltx-image` | LTX-2.5 | `input_image` |
| `video-ltx-first-last` | LTX-2.5 | `input_image`, `last_image` |

Each workflow JSON carries the HuggingFace URL for every model it loads, so the download list is the file itself. The shipped graphs have their prompts blanked to `prompt text` — you always supply your own, so there is nothing to inherit.

There is a ready-made message per flow in `automation-examples/inbox/`. Flip `comfy`'s `enabled: true`, restart automation, then copy one and edit it:

```bash
cp automation-examples/inbox/comfy-image-text.md automation/inbox/
```

The message body is the prompt, and `output_prefix` is the filename prefix ComfyUI writes under.
Everything else a workflow exposes is an env-style message parameter of the same name — set one
to override the workflow's own value, leave it out to keep it:

| Parameter | Applies to |
|---|---|
| `width`, `height` | the Flux, Wan and LTX first/last flows — and an override on the other two LTX flows |
| `aspect_ratio`, `megapixels` | `video-ltx-text` and `video-ltx-image`, which size themselves through a `ResolutionSelector` |
| `duration`, `fps` | the LTX flows — `duration` is seconds, not frames |
| `length` | `video-i2v`, in frames |
| `seed` | any flow with a sampler; randomized when unset |
| `enhance_prompt` | the LTX flows — rewrites the prompt through a local LLM before encoding |

`image-qwen-angles` is the batch flow: one input image, up to eight edits of it in a single
queue. Its body is a YAML list instead of prompt text, so a prompt sits next to the name its
output gets (`automation-examples/inbox/comfy-image-qwen-angles.md`):

```yaml
---
routine: comfy
type: image-qwen-angles
input_image: example.png
---
- prompt: prompt text
  output: images/example-1
- prompt: prompt text
  output: images/example-2
```

Fewer than eight entries prunes the unused branches out of the submitted graph, so they cost no
GPU time. There is no size parameter for this flow — the output resolution follows `input_image`.
Long lists can live in a file instead of the body, via `items_file`.

Every flow is fire-and-forget: the routine POSTs and exits on the HTTP code, and ComfyUI writes
the result into its own `output/`. To do something with the file afterwards, poll `/history/{id}`
until `outputs` appears and fetch it from `/view`.

## Running a batch of prompts

Every prompt against every reference image, with no new code. There is no separate
"working directory" to set up — ComfyUI's own `input/` folder **is** it, and on the host that
is a plain bind mount at `volumes/comfyui_data/ComfyUI/input/`. Anything you drop there,
ComfyUI knows by name immediately.

**1. Put your reference images somewhere under `input/`.** A subfolder keeps a project together:

```bash
mkdir -p volumes/comfyui_data/ComfyUI/input/hero
cp ~/refs/*.png volumes/comfyui_data/ComfyUI/input/hero/
```

**2. Write your prompts, one per line,** in a file anywhere — this one is not a decree message,
just a list. Blank lines are skipped:

```
a portrait on the front steps at golden hour
the same subject in heavy fog, wide shot
```

**3. Fan them out.** From the repo root, this writes one inbox message per
(prompt × image) — the cross product:

```bash
DIR=volumes/comfyui_data/ComfyUI/input/hero; STAMP=$(date +%H%M%S); n=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  for img in "$DIR"/*.png; do
    n=$((n+1))
    cat > "automation/inbox/comfy-$STAMP-$n.md" <<EOF
---
routine: comfy
type: image-text-image
input_image: "hero/$(basename "$img")"
output_prefix: hero/out-$n
---
$p
EOF
  done
done < prompts.md
```

Drop the inner `for` loop, the `input_image` line, and `$DIR` for `type: image-text` — that flow
takes no reference image, so it is one message per prompt.

**4. Watch it go.** Results land in `volumes/comfyui_data/ComfyUI/output/hero/`, and the queue is
visible in ComfyUI's own UI.

```bash
docker logs -f automation
```

Two things to know before you point this at a large folder. The routine POSTs and exits, so
twenty messages become twenty ComfyUI queue entries in about a second — the depth is ComfyUI's
problem, not decree's, and a few hundred is an unattended GPU night. And nothing here dedupes:
re-running the loop queues the whole cross product again, which is usually what you want (seeds
are randomized) but is worth knowing.

## Triggering over HTTP

Two endpoints ship in `services/automation/webhook/config.exist.yml`, so anything that can POST
can queue a generation. The request body is the prompt:

```bash
# No reference image
curl -X POST https://automation-webhook.EXIST_DOMAIN/comfy/image-text/sunset \
  -H "Authorization: Bearer $SECRET" \
  -d 'a sunset over mountains'

# With one — "ref.png" must already be in ComfyUI's input/
curl -X POST https://automation-webhook.EXIST_DOMAIN/comfy/image-text-image/edit1/ref.png \
  -H "Authorization: Bearer $SECRET" \
  -d 'the same scene at night'

# With two — video-ltx-first-last anchors the first and last frames
curl -X POST https://automation-webhook.EXIST_DOMAIN/comfy/video-ltx-first-last/pan/a.png/b.png \
  -H "Authorization: Bearer $SECRET" \
  -d 'a slow camera push between the two frames'
```

The secret is the top-level `secret:` in the rendered `services/automation/webhook/config.yml`.
Output goes to `output/comfy/<name>/`.

The shape is dictated by two deliberate properties of the webhook, both documented in
`services/automation/webhook/README.md`: **the body is never parsed** — it is opaque bytes
copied into the message body verbatim — and
**frontmatter is fixed per endpoint**. So the prompt is the body and everything else has to be a
path parameter. That has two consequences worth internalising:

- **A path parameter cannot contain `/`**, so these routes reach only images sitting directly in
  `input/`, never in a subfolder. That is not fixable by adding a `{sub}` segment: the resulting
  `/comfy/{type}/{name}/{sub}/{image}` is the same *shape* as the two-image route, routes are
  registered on a `ServeMux`, and it panics on conflicting patterns — a fatal startup error. The
  `params:` regexes cannot separate them either, because they are applied after routing, not
  during it. Keep webhook reference images flat in `input/`; use the batch loop above for
  subfolders.
- **There is no optional parameter**, which is why each image count is its own route. Every
  additional knob (`width`, `duration`, `seed`, …) would likewise be another path segment or
  another endpoint with the value baked in — for anything more elaborate, write the inbox message
  directly, as the batch loop above does. That applies especially to `video-ltx-first-last`,
  which reaches its real settings (`duration`, `fps`, `width`, `height`) only that way.

Both routes set an explicit `params:` pattern. The default parameter charset is
`[A-Za-z0-9_\-!]+`, which has no `.`, so `ref.png` would be rejected with a `400` without one.

:::warning Editing the config needs a recreate, not a restart
The service polls `config.yml` and exits on change so its restart policy reloads it — but it
compares the **mtime of the inode it already holds**, and `config.yml` is a single-file bind
mount. An editor that writes to a temp file and renames it (most of them) leaves that inode
untouched, so the running process never notices, and `docker cp` will happily show you the new
content while the process serves the old. Use `docker compose up -d --force-recreate
automation-webhook` and confirm the route count in `docker logs automation-webhook`.
:::

## Telegram → ComfyUI Workflow

Nothing wires Telegram to ComfyUI out of the box — the shipped `telegram-ingest` routine
(`automation/shared_routines/telegram-ingest.sh`) polls for inbound *photo* messages and
routes them into the OCR pipeline, not text commands. A `/imagine <prompt>` workflow is
something you'd write yourself, following the same shape:

```
User sends: /imagine a sunset over mountains
        │
        ▼
your routine polls the Telegram Bot API (see telegram-ingest.sh for the pattern)
        │
        ▼
Extracts the prompt, POSTs the workflow to comfyui:8188/prompt
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

See [Telegram integration](../integrations/telegram) for bot credentials setup, and
[Writing a Routine](../writing-a-routine) for how a new routine gets registered and run
on a schedule.

## Designing Workflows

Adding a flow to the `comfy` routine is adding two files to
`automation/lib/comfy/workflows/` — a graph and a binding. No shell is written:

1. Open `https://comfyui.EXIST_DOMAIN`, build the workflow visually, and run it once so you know
   it works.
2. Export it as **`Workflow → Export (API)`** — the flat node map `/prompt` accepts, distinct
   from the regular save format, which is UI layout. Subgraphs are flattened on the way out, so
   node ids in the export do not match the ids you see on the canvas. Save it into
   `workflows/`. (Copying the browser's `POST /api/prompt` request body out of devtools works
   too, and keeps the UI graph so generated files re-open as a working workflow.)
3. Write `workflows/<type>.yml` beside it, naming each parameter you want to control and the node
   and input it writes to. Copy the closest existing binding — `video-ltx-text.yml` for a plain
   flow, `image-qwen-angles.yml` for a batch one.
4. `./existential.sh test unit` — `test-comfy-workflows.sh` checks every binding against its
   graph.

Node ids are the fragile part: re-exporting a workflow renumbers everything, and a binding that
points at a node which no longer exists would otherwise submit the untouched template and return
an image of somebody else's prompt. Both `patch.ts` and the unit test refuse a binding that does
not resolve, so a re-export fails loudly instead.

Seeds are randomized by default, so a re-run of the same message gives fresh images. Pass an
explicit `seed` when you want to reproduce one.

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
