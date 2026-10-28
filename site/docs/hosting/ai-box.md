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
[Configuration → Endpoints](../configuration#endpoints--putting-roles-on-different-machines).

## The VRAM rule: nothing swaps automatically

One 24 GB card fits **one** GPU-heavy service at a time. No service on the box knows another is
there. llama.cpp does not unload for ComfyUI, ComfyUI does not free memory for TTS, and a
service that cannot get its VRAM fails, usually on its first request rather than at startup.
So every switch is explicit:

- llama.cpp holds at most `--models-max` models. Set it to `1`, so loading a model unloads
  the last one. It counts models and never checks free VRAM.
- TTS is off until something asks for it, and is stopped when the work is done
  ([below](#tts-started-and-stopped-over-http)).
- Before starting anything big, check `nvidia-smi` to see what is holding the card, then
  unload the model the router holds:
  `curl -X POST http://<ai-box>:8080/models/unload -d '{"model": "<chat-model>"}'`.

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

[<embed-model>]
model = /models/<embed-model>.gguf
embeddings = true
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
EXIST_MODEL_EXTRACT=<chat-model>
EXIST_MODEL_VISION=<chat-model>           # its section needs an mmproj = projector
EXIST_MODEL_EMBED=<embed-model>           # its section needs embeddings = true
```

The rules in [Configuration → Models](../configuration#models) still apply, the 64k context
floor included. Only ollama enforces them for you, so here they are yours to keep.

## ComfyUI

ComfyUI runs on the box in its own GPU container and listens on its usual `8188`. The stack's
side is two keys:

```bash
EXIST_COMFYUI_URL=http://<ai-box>:8188
EXIST_IS_AI_COMFYUI=false
```

The workflows stay in this repo. The checkpoints they name must exist on the box. See
[ComfyUI → Using a ComfyUI you already run](../ai/comfyui#using-a-comfyui-you-already-run).
Free the card before a big job: `--models-max 1` keeps one model loaded, not zero.

## TTS, started and stopped over HTTP

Qwen3-TTS needs most of the card while it runs, so it is not left up. The box runs its own
[decree](../decree/decree.md) project with
[decree-go-rest](../build-on-it) in front of it. Two endpoints
start and stop TTS:

```yaml
# .decree/decree-go-rest.yml on <ai-box>
endpoints:
  - path: /startTTS
    message: { machine: start_tts }
  - path: /endTTS
    message: { machine: end_tts }
```

Each machine is one state that invokes a script of the same name. The scripts run TTS in a
named tmux session with `tmx` (from this repo's `services/automation/decree/tmx.sh`, sourced in
the box's `~/.bashrc`), so "is it running?" is `tmux has-session -t =tts` and a person can
`tmx tts` to watch it:

```bash
# .decree/scripts/start_tts.sh
tmx -d tts '<your Qwen3-TTS server command>'

# .decree/scripts/end_tts.sh
tmux kill-session -t =tts 2>/dev/null || true
```

`tmx -d` does nothing if the session is already up, so a second `/startTTS` is harmless. Unload
the router's model before the start call, because nothing else will.

```bash
curl -X POST http://<ai-box>:8801/startTTS -H "Authorization: Bearer <secret>"
# ... generate speech ...
curl -X POST http://<ai-box>:8801/endTTS -H "Authorization: Bearer <secret>"
```

**There is no stack key for this.** The stack's own speech is wyoming-piper on CPU
([Speech has no endpoint keys](../configuration#speech-has-no-endpoint-keys)), so whatever
calls Qwen3-TTS uses the box's address directly.

## GLiNER on CPU

The GLiNER classifier runs on the CPU, so it uses no VRAM and can stay up next to everything
else. A decree machine can use it as a typed router, a classifier that picks one of the labels
it is given. Like TTS, it has no stack key.

## Summary of stack keys

| Service on `<ai-box>` | Stack keys |
|---|---|
| llama.cpp router | `EXIST_MODEL_URL` (or one `EXIST_MODEL_URL_<ROLE>` per role), `EXIST_MODEL_*` set to preset names, `EXIST_IS_AI_OLLAMA=false` |
| ComfyUI | `EXIST_COMFYUI_URL`, `EXIST_IS_AI_COMFYUI=false` |
| Qwen3-TTS | none (start and stop it through the box's `/startTTS` and `/endTTS`) |
| GLiNER | none |

Then `./existential.sh && docker compose up -d`, and `./existential.sh run models` to confirm
where each role resolves.
