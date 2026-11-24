---
name: gpu_lease
extends: decree_lease
x-exist-project: automation
needs:
  - model
  - gpu_release
scripts:
  resources: |
    # What can be leased: one GPU, in mode llm (ollama's models) or comfy (ComfyUI's).
    # name  max_lease  linger  max_wait  modes      holders
    gpu     30m        5s      30m       llm,comfy  4
  swap/gpu.sh: |
    #!/usr/bin/env bash
    # gpu.sh <from> <to>: free the GPU for <to>, letting the other mode's work finish first.
    set -euo pipefail
    source ".decree/lib/model.sh"
    comfy="${EXIST_COMFYUI_URL:-http://comfyui:8188}"
    case "$2" in
        llm)    # ComfyUI: its queue empties, then its models are unloaded.
            curl -fsS --max-time 5 "${comfy}/queue" >/dev/null 2>&1 || exit 0
            until curl -fsS --max-time 5 "${comfy}/queue" | jq -e '(.queue_running + .queue_pending) | length == 0' >/dev/null; do sleep 5; done
            curl -fsS --max-time 60 -X POST "${comfy}/free" -H 'Content-Type: application/json' \
                -d '{"unload_models": true, "free_memory": true}' >/dev/null ;;
        comfy)  # ollama: every resident model is unloaded. Another server has no /api/ps, and nothing to do.
            root="$(model_url chat)"; root="${root%/v1}"
            for m in $(curl -fsS --max-time 5 "${root}/api/ps" 2>/dev/null | jq -r '.models[]?.model'); do
                jq -nc --arg m "$m" '{model: $m, keep_alive: 0}' |
                    curl -fsS --max-time 60 "${root}/api/generate" -H 'Content-Type: application/json' -d @- >/dev/null
            done ;;
    esac
    echo "gpu_lease: the GPU is free for $2"
  callback.sh: |
    #!/usr/bin/env bash
    # The holder is told at the address automation/.env names for it,
    # GPU_LEASE_CALLBACK_<HOLDER>, never at one a request names: a POST to the stack
    # cannot make it POST anywhere else. Then decree_lease's own callback step.
    set -euo pipefail
    var="GPU_LEASE_CALLBACK_$(tr 'a-z-' 'A-Z_' <<<"${DECREE_DATA_HOLDER:-}")"
    [[ "${DECREE_DATA_HOLDER:-}" =~ ^[a-z0-9_-]+$ ]] && export DECREE_DATA_CALLBACK="${!var:-}" || export DECREE_DATA_CALLBACK=
    exec bash .decree/machines/decree_lease/scripts/callback.sh
x-exist-endpoints:
  - path: /gpu/{mode}/{client}
    patterns: {mode: "llm|comfy", client: "[a-z0-9_-]{1,40}"}
    body: optional
    message:
      machine: gpu_lease
      params: {resource: gpu, mode: "{{mode}}", holder: "{{client}}"}
---
# GPU lease

One GPU, shared by anything that can POST: decree's `decree_lease`, with this stack's one
resource, `gpu`. A lease in mode `llm` unloads ComfyUI's models first, and one in `comfy`
unloads ollama's. Up to four leases in the mode the GPU is in hold it together; a lease in the
other mode waits for them, and the mode that is loaded goes first, as long as nobody waits more
than 30 minutes.

## Using it

1. `POST /gpu/<mode>/<client>` on automation-webhook asks for the GPU. The answer's `id` is
   the lease.
2. When the lease holds the GPU, the stack POSTs the lease's status (`{"run": "<id>", "mode":
   ..., "state": "granted", "expires": ...}`) to `GPU_LEASE_CALLBACK_<CLIENT>` in
   `automation/.env` (a client `my-box` is `GPU_LEASE_CALLBACK_MY_BOX`; a token goes in its
   query string). Without one, the client is not told. A callback that does not answer `2xx`
   ends the lease.
3. `POST /gpu/lease/<id>/release` when done (or to leave the line), or `/renew` for another
   30 minutes while nobody waits. A lease nobody releases ends 30 minutes after it was granted.

The rules (`scripts/resources`) and the swap (`scripts/swap/gpu.sh`) are this file's, so they
install read-only with it; the line and each lease's status are in its `state/`.

## What it does not do

Only clients that ask take part. A ComfyUI prompt or model call that does not ask uses the GPU
anyway; `llm` waits for ComfyUI's queue to empty before unloading it.
