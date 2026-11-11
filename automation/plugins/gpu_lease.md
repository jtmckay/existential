---
machine: plugin
automation: gpu_lease
needs:
  - model
chart:
  description: One GPU, one holder at a time. A lease waits its turn in line, frees the GPU for its mode, and holds it until released or 30 minutes pass.
  data:
    mode: {type: string, default: llm, enum: [llm, comfy]}
    client: {type: string, default: ""}
    # A message with lease set answers that lease instead of asking for one.
    lease: {type: string, default: ""}
    answer: {type: string, default: release, enum: [release, renew]}
  store:
    queue: Lease ids, oldest first; the first holds the GPU. start adds, next removes.
  initial: start
  states:
    start:
      invoke: start
      transitions: {done: wait, go: swap, released: done}
    wait:
      invoke:
        person:
          question: Is it this lease's turn for the GPU?
          ask: queued
          timeout: 1m
      transitions:
        go: {target: swap, description: "First in line, so the GPU is this lease's."}
        release: {target: done, description: "Give up this place in line."}
        # Every minute it looks again, so a wake that came too early is never lost.
        error: start
    swap:
      invoke:
        script: {name: swap, timeout: 30m}
      transitions: {done: held}
    held:
      invoke:
        person:
          question: Done with the GPU?
          ask: grant
          timeout: 30m
      transitions:
        release: {target: done, description: "The holder is done with the GPU."}
        renew: {target: held, description: "Keep the GPU another 30 minutes."}
        error: done
    done: {final: true, onentry: [next]}
    failed: {final: true, onentry: [next]}
scripts:
  start: |
    #!/usr/bin/env bash
    # A lease joins the line and goes when it is first. A message with lease set
    # passes its answer to that lease, which must be one in line.
    set -euo pipefail
    q="${DECREE_STORE}/queue"; touch "$q"
    if [[ -n "${DECREE_DATA_LEASE:-}" ]]; then
        grep -qxF "$DECREE_DATA_LEASE" "$q" || { echo "gpu_lease: ${DECREE_DATA_LEASE} is not a lease in line" >&2; exit 1; }
        "${DECREE:-decree}" event "$DECREE_DATA_LEASE" "$DECREE_DATA_ANSWER"
        echo released > "$DECREE_EVENT_FILE"; exit 0
    fi
    me="$DECREE_MESSAGE_ID"
    grep -qxF "$me" "$q" || echo "$me" >> "$q"
    # A finished run in front ended without leaving the line: it holds nothing.
    while first="$(head -1 "$q")"; [[ -n "$first" && "$first" != "$me" ]] &&
          [[ "$("${DECREE:-decree}" status "$first" --format json 2>/dev/null | jq -r '.status // "finished"')" == finished ]]; do
        sed -i 1d "$q"
    done
    [[ "$(head -1 "$q")" != "$me" ]] || echo go > "$DECREE_EVENT_FILE"
  queued: |
    #!/usr/bin/env bash
    # Says where the lease is in line; the turn comes from next, or from start a minute on.
    set -euo pipefail
    echo "gpu_lease: number $(grep -nxF "$DECREE_MESSAGE_ID" "${DECREE_STORE}/queue" | cut -d: -f1) in line, behind $(head -1 "${DECREE_STORE}/queue")"
  swap: |
    #!/usr/bin/env bash
    # Free the GPU for this lease's mode: let the other mode's work finish, then unload it.
    set -euo pipefail
    source "${DECREE_LIB}/model.sh"
    comfy="${EXIST_COMFYUI_URL:-http://comfyui:8188}"
    case "$DECREE_DATA_MODE" in
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
    echo "gpu_lease: the GPU is free for ${DECREE_DATA_MODE}"
  grant: |
    #!/usr/bin/env bash
    # Tell the client it holds the GPU: POST {"lease", "mode"} to GPU_LEASE_CALLBACK_<CLIENT>
    # in automation/.env, with GPU_LEASE_CALLBACK_<CLIENT>_TOKEN as its bearer if set.
    set -euo pipefail
    [[ "${DECREE_VISITS:-1}" == 1 ]] || exit 0      # a renewal: the client already knows
    client="${DECREE_DATA_CLIENT:-}"
    [[ "$client" =~ ^[a-z0-9_-]+$ ]] || { echo "gpu_lease: no client to tell"; exit 0; }
    var="GPU_LEASE_CALLBACK_$(tr 'a-z-' 'A-Z_' <<<"$client")"; tok="${var}_TOKEN"
    url="${!var:-}"
    [[ -n "$url" ]] || { echo "gpu_lease: no ${var}, so ${client} is not told"; exit 0; }
    auth=(); [[ -z "${!tok:-}" ]] || auth=(-H "Authorization: Bearer ${!tok}")
    jq -nc --arg l "$DECREE_MESSAGE_ID" --arg m "$DECREE_DATA_MODE" '{lease: $l, mode: $m}' |
        curl -fsS --max-time 10 --retry 3 -X POST "$url" -H 'Content-Type: application/json' "${auth[@]}" -d @- >/dev/null ||
        echo "gpu_lease: ${url} did not answer; the lease runs out on its own" >&2
  next: |
    #!/usr/bin/env bash
    # The lease is over: it leaves the line, and whoever is first now is woken.
    set -euo pipefail
    q="${DECREE_STORE}/queue"
    [[ -f "$q" ]] && grep -qxF "$DECREE_MESSAGE_ID" "$q" || exit 0
    grep -vxF "$DECREE_MESSAGE_ID" "$q" > "${q}.new" || true
    mv "${q}.new" "$q"
    first="$(head -1 "$q")"
    # Only a hint: a lease not yet waiting finds its turn on its own within a minute.
    [[ -z "$first" ]] || "${DECREE:-decree}" event "$first" go >/dev/null 2>&1 || true
endpoints:
  - path: /gpu/{mode}/{client}
    patterns: {mode: "llm|comfy", client: "[a-z0-9_-]{1,40}"}
    body: optional
    message:
      machine: gpu_lease
      params: {mode: "{{mode}}", client: "{{client}}"}
  - path: /gpu/lease/{lease}/{answer}
    patterns: {lease: "[0-9A-Za-z._-]{1,80}", answer: "release|renew"}
    body: optional
    message:
      machine: gpu_lease
      params: {lease: "{{lease}}", answer: "{{answer}}"}
---
# GPU lease

One GPU, shared by anything that can POST, one holder at a time. The holder gets the GPU in
its mode: `llm` unloads ComfyUI's models, `comfy` unloads ollama's. Nobody coordinates with
anybody else; each one asks and waits its turn.

## Using it

1. `POST /gpu/<mode>/<client>` on automation-webhook asks for the GPU. The answer's `id` is
   the lease.
2. When the lease is first in line and the GPU is free for its mode, the stack POSTs
   `{"lease": "<id>", "mode": "<mode>"}` to `GPU_LEASE_CALLBACK_<CLIENT>` (in
   `automation/.env`; a client `my-box` is `GPU_LEASE_CALLBACK_MY_BOX`, with
   `GPU_LEASE_CALLBACK_MY_BOX_TOKEN` as its bearer). Without one, the client is not told.
3. `POST /gpu/lease/<id>/release` when done, or `/renew` for another 30 minutes. A lease
   nobody releases ends 30 minutes after it was granted, and the next one goes.

A release sent in the instant after the callback can arrive before the lease is waiting
for it; that release fails, and sending it again works.

## What it does not do

- Leases are taken in the order they arrive, one at a time, even two in the same mode.
- Only clients that ask take part. A ComfyUI prompt or model call that does not ask uses
  the GPU anyway; `llm` waits for ComfyUI's queue to empty before unloading it.
- A lease whose run was interrupted keeps its place in line until it is retried or ended
  (`decree process --retry <id>`), so a crash never hands the GPU to two holders.
