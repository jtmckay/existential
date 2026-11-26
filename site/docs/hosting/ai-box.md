---
sidebar_position: 13
---

# A Separate AI Box

The stack does not have to share a machine with its GPU. Models, image generation and speech
can run on another box, `<ai-box>` below, and the stack reaches them over a URL. This page walks
through one real setup: a single 24 GB card, rootless podman with NVIDIA CDI, llama.cpp in
router mode, ComfyUI, Qwen3-TTS, and a GLiNER classifier on CPU.

Nothing on `<ai-box>` is part of the stack. It runs no existential compose file, and the stack
only ever sees the addresses below. Which keys exist and how they fall back is in
[Configuration → Endpoints](../configuration.md#endpoints--putting-roles-on-different-hosts).

## One card, taken in turns

One 24 GB card fits **one** GPU-heavy service at a time, and no service on the box knows another
is there: llama.cpp does not unload for ComfyUI, ComfyUI does not free memory for TTS, and a
service that cannot get its VRAM fails on its first request. `lease_gpu` makes the switch
for you. Turn it on in the box's own checkout (`./existential.sh plugin on lease_gpu`), and its host
daemon gets `lease_gpu`, decree's `decree_lease` with one resource, `gpu`, in mode `llm`,
`comfy`, `tts` or `strata`. A lease in one mode frees the card first: the llama.cpp router
unloads its models, ComfyUI finishes its queue and unloads, TTS and Strata stop. A `tts` or
`strata` lease then starts its server. Up to four leases share it
in one mode; another mode waits for them, and none waits more than 30 minutes for its turn.

```bash
decree emit --machine lease_gpu --param resource=gpu --param mode=comfy --param holder=me </dev/null
# ... the lease's id is printed; when its status says granted, use the card ...
decree reply <lease id> release
```

Only work that asks takes part. A chat request or a ComfyUI prompt sent straight to the box
still loads its model, so keep llama.cpp at `--models-max 1` (loading a model unloads the last)
and check `nvidia-smi` when a request fails for memory. `lease_gpu` needs Linux (`flock`), and it
reads `.decree/.env` on the box: `AI_BOX_LLAMA_URL` and `AI_BOX_COMFYUI_URL` when they are not on
`localhost:8080` and `localhost:8188`, and `AI_BOX_TTS_COMMAND` (below).

### From another host

With [decree-go-rest](#leases-from-another-host) in front of the box's `.decree`, the
lease is served over HTTP too, each call with the bearer secret:

| Call | What it does |
|---|---|
| `POST /gpu/<mode>/<client>` | Ask for the card in mode `llm`, `comfy`, `tts` or `strata`; the answer's `id` is the lease |
| `GET /gpu/lease/<id>` | The lease's status: its `state` is `granted` or `held` once it holds the card |
| `POST /gpu/lease/<id>/release` | Give it back (`/renew`: keep it for its duration again) |
| `GET /gpu` | The card: its mode, holders and line |

The box also tells the other hosts what it serves and where to lease it, in each report, so
they find it by asking the controller: `./existential.sh run peers` on any host
([Peers](./controller-and-workers.md#peers-what-the-other-hosts-offer)). The stack's own
model calls and ComfyUI runs lease it this way on their own ([Leases](./controller-and-workers.md#leases)).
`AI_BOX_SERVICES` in `.decree/.env` (default `llm,comfy,tts`) is what the box offers: take one
out to [move it to another host](./controller-and-workers.md#moving-a-service-to-another-host).

## GPU containers: rootless podman with CDI

With the NVIDIA Container Toolkit installed, generate the CDI spec once
(`sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`). After that a rootless container
gets the card with `--device nvidia.com/gpu=all`, without a daemon or root. Re-run the generate
step after a driver upgrade.

## llama.cpp in router mode

Started with no `-m`, `llama-server` runs as a **router**. It loads the model each request
names, from a preset file, in a child process of its own. Every model then sits behind one
OpenAI-compatible `/v1`. The image already listens on every interface, on port 8080:

```bash
podman run -d --name llama --device nvidia.com/gpu=all -p 8080:8080 \
  -v ~/models:/models:ro ghcr.io/ggml-org/llama.cpp:server-cuda \
  --models-preset /models/presets.ini --models-max 1
```

The presets are an INI file. Each section is a model name, and its keys are `llama-server`
flags without the leading `--`. `[*]` holds what every model shares:

```ini
[*]
flash-attn = on

[<chat-model>]
model = /models/<chat-model>.gguf
ctx-size = 65536
cache-type-k = q8_0
cache-type-v = q8_0

```

**The V-cache type is set per model, never on the command line.** The router passes its own
command-line flags to every model it starts, so a flag there applies to all of them. A
quantized V cache only works with flash attention, and not every model supports that, so a
global `--cache-type-v` breaks those models. In the preset, each model keeps the cache that
suits it. The KV cache is also where a long context costs VRAM, which makes it the setting most
worth tuning for each model.

The section name is the model name the stack sends, so set the *Model Selection* keys to those
names:

```bash
EXIST_IS_AI_OLLAMA=false                  # nothing local to pull or serve
EXIST_MODEL_URL=http://<ai-box>:8080/v1
EXIST_MODEL_CHAT=<chat-model>             # a [section] in presets.ini
EXIST_MODEL_VISION=<chat-model>           # its section needs an mmproj = projector
```

The rules in [Configuration → Models](../configuration.md#models) still apply, the 64k context
floor included. Only ollama enforces them for you, so here they are yours to keep.

## ComfyUI

ComfyUI runs on the box itself, from its own checkout, in a tmux session the host daemon starts.
Install it once (PyTorch first, for your card; ComfyUI's README names the wheel index for each
GPU):

```bash
git clone https://github.com/Comfy-Org/ComfyUI.git ~/ComfyUI
cd ~/ComfyUI
python3.12 -m venv .venv
.venv/bin/pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130
.venv/bin/pip install -r requirements.txt
```

Then start it at boot with `boot_daemon` (`./existential.sh plugin on boot_daemon`): one line in
`.decree/boot.sh`, which runs once each time the host daemon starts.

```bash
# .decree/boot.sh on <ai-box>
tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0 --port 8188'
```

On another port, set `AI_BOX_COMFYUI_URL` in `.decree/.env`. The other hosts lease it; on
each, `EXIST_IS_AI_COMFYUI=false` keeps a local one from starting.

The workflows stay in this repo. The checkpoints they name must exist on the box, under
`~/ComfyUI/models/`. See
[ComfyUI → Using a ComfyUI you already run](../ai/comfyui.md#using-a-comfyui-you-already-run).
A `comfy` lease frees the card first: `--models-max 1` keeps one model loaded, not zero.

## Strata, a fourth mode

[Strata](../ai/strata.md) serves a mixture-of-experts model too big for the card across VRAM,
RAM and SSD. Unlike llama.cpp it loads its model when it starts, so on an AI box the lease runs
it: a `strata` lease stops everything else and starts Strata, and any other mode stops it. It
is the `ai/strata` service's image and model pack, in a container of the lease's own
(`ai-box-strata`), so leave the `strata` service off on the box: compose's `up -d` would start
it again behind the lease. Its downloads stay in `volumes/strata_cache`.

```bash
# .decree/.env on <ai-box>
AI_BOX_SERVICES=llm,comfy,tts,strata
AI_BOX_STRATA_FAMILY=qwen
AI_BOX_STRATA_MODEL=IQ3_S
# AI_BOX_STRATA_PORT=8081   # where it listens on the box (8080 is llama.cpp's)
AI_BOX_STRATA_CONTEXT=262144  # the model's full context (default 65536)
# AI_BOX_STRATA_MEMORY=64g    # its RAM cap (the default)
```

Strata fills the RAM it is given with cached experts. On a 24 GB card, 64 GB serves the full
262144 context at full speed (about 100 tokens/s; a 250k-token prompt in about 90 s) and uses
about 57 GiB of it. Below about 64 GB Strata keeps more of its context in VRAM, which leaves
less room for experts and slows it down; more than 64 GB gains nothing. Less RAM means more reads
from the SSD, not a failure. Its key is `EXIST_FLEET_SECRET` from the box's `.env.shared`, the same on every host that calls
it. A lease that starts Strata is granted once it serves a model, which takes minutes; fetch a
new pack first (`ai/strata`'s own `docker compose up -d strata` on the box, then stop it) so a
download never runs inside a lease. A host whose model calls should go to Strata sets its
`EXIST_MODEL_CHAT` to the id Strata serves (`./existential.sh run peers strata --json` lists it).

## TTS, a lease like the others

Qwen3-TTS needs most of the card while it runs, so it runs only under a `tts` lease. The lease
stops everything else, then runs `AI_BOX_TTS_COMMAND` in a tmux session named `tts`
(`tmux attach -t tts` watches it), and is granted once the server answers on
`AI_BOX_TTS_URL` (default `http://localhost:8000`). If it exits, it starts again; any other
mode ends the session. Released, it stays up until another mode needs the card, so the next
TTS lease is granted at once.

Install it once, in an environment of its own (Python 3.12, as its README asks):

```bash
conda create -n qwen3-tts python=3.12 -y
conda run -n qwen3-tts pip install -U qwen-tts
```

The model downloads from Hugging Face the first time the server starts (a few GB, into
`~/.cache/huggingface`), so that first start is slow; run it once by hand to see it through.
FlashAttention 2 (`pip install -U flash-attn --no-build-isolation`) saves VRAM but is optional;
without it, keep `--no-flash-attn`. Then name the command in `.decree/.env`, by the full path of
the environment's `qwen-tts-demo` (`conda run -n qwen3-tts which qwen-tts-demo`), since the
daemon does not activate conda:

```bash
# .decree/.env on <ai-box>
AI_BOX_TTS_COMMAND=~/miniconda3/envs/qwen3-tts/bin/qwen-tts-demo Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign --device cuda:0 --dtype bfloat16 --no-flash-attn --ip 0.0.0.0 --port 8000
```

`VoiceDesign` makes a voice from a description; the README's other models are `CustomVoice`
(its named speakers) and `Base` (clones a voice from a sample). The server answers on `:8000`,
the Gradio UI and its API.

## Leases from another host

For another host to take a lease, the box needs [decree-go-rest](../plugins/http.md) in front of
its `.decree`, on `:8801` with the fleet's secret ([Leases](./controller-and-workers.md#leases)).
One command writes its config (`.decree/decree-go-rest.yml`, the box's own), starts it, and adds
it to `.decree/boot.sh` with `boot_daemon`, so it starts at boot; each plugin adds its
endpoints at each `./existential.sh`:

```bash
./existential.sh run fleet api
```

It only queues messages; the host daemon runs them.

Another host's decree scripts then take and give back leases through the `fleet` lib
([Leases](./controller-and-workers.md#leases)), or by hand:

```bash
id=$(./existential.sh run peers lease <ai-box> tts my-job)
# ... generate speech at http://<ai-box>:8000 ...
./existential.sh run peers release <ai-box> tts "$id"
```

**There is no stack key for TTS.** The stack's own speech is wyoming-piper on CPU
([Speech has no endpoint keys](../configuration.md#speech-has-no-endpoint-keys)), so whatever
calls Qwen3-TTS leases it and uses the box's address directly.

## Checking it works

With the host daemon running and `lease_gpu` on:

1. `id=$(./existential.sh run peers lease <ai-box> tts check)` returns once TTS answers:
   `tmux has-session -t =tts` on the box, and `curl -I http://<ai-box>:8000/`.
2. `jq . .decree/machines/lease_gpu/state/status/resources/gpu.json` shows mode `tts` and one
   holder.
3. `./existential.sh run peers release <ai-box> tts "$id"`: the holders list is empty. A lease
   in another mode ends the session, and `nvidia-smi` shows the memory back.

A run that failed is in `decree status`, its log under `.decree/runs/<id>/`.

## GLiNER on CPU

The GLiNER classifier runs on the CPU, so it uses no VRAM and can stay up next to everything
else. A decree machine can use it as a typed router, a classifier that picks one of the labels
it is given. Like TTS, it has no stack key.

## Summary of stack keys

| Service on `<ai-box>` | Stack keys |
|---|---|
| llama.cpp router | `EXIST_MODEL_*` set to model ids it offers (leased), `EXIST_MODEL_URL` for apps that cannot lease, `EXIST_IS_AI_OLLAMA=false` |
| ComfyUI | `EXIST_IS_AI_COMFYUI=false` (leased) |
| Qwen3-TTS | none (lease it: `tts`) |
| GLiNER | none |

Then `./existential.sh && docker compose up -d`, and `./existential.sh run models` to confirm
where each role resolves.
