---
name: ai_box_gpu
extends: decree_lease
x-exist-project: host
scripts:
  resources: |
    # A separate AI box's one card: one GPU-heavy service at a time.
    #   name  max_lease  linger  max_wait  modes         holders
    # Modes: llm (the llama.cpp router), comfy (ComfyUI), tts (the TTS server ai_box_tts starts).
    # Up to four leases share the card in one mode; another mode waits for all of them.
    gpu     4h         5s      30m       llm,comfy,tts  4
  swap/gpu.sh: |
    #!/usr/bin/env bash
    # gpu.sh <from> <to>: free the card for <to> by stopping every other GPU user. <to> loads
    # on demand (llama.cpp, ComfyUI) or is started by whoever asked (ai_box_tts). A service
    # that does not answer holds nothing. Addresses and the session name: .decree/.env.
    set -euo pipefail
    to="$2"
    llm="${AI_BOX_LLAMA_URL:-http://localhost:8080}"
    comfy="${AI_BOX_COMFYUI_URL:-http://localhost:8188}"
    tts="${AI_BOX_TTS_SESSION:-tts}"
    free_llm() {  # unload every model the llama.cpp router has loaded or is loading
        local models m
        models="$(curl -fsS --max-time 10 "${llm}/models" 2>/dev/null |
            jq -r '.data[] | select(.status.value == "loaded" or .status.value == "loading") | .id')" ||
            { echo "llm: no answer at ${llm}"; return 0; }
        for m in $models; do
            jq -nc --arg m "$m" '{model: $m}' |
                curl -fsS --max-time 120 -X POST "${llm}/models/unload" -H 'Content-Type: application/json' -d @- >/dev/null
            echo "llm: unloaded ${m}"
        done
    }
    free_comfy() {  # its queue empties, then its models are unloaded
        curl -fsS --max-time 5 "${comfy}/queue" >/dev/null 2>&1 || { echo "comfy: no answer at ${comfy}"; return 0; }
        until curl -fsS --max-time 5 "${comfy}/queue" | jq -e '(.queue_running + .queue_pending) | length == 0' >/dev/null; do sleep 5; done
        curl -fsS --max-time 60 -X POST "${comfy}/free" -H 'Content-Type: application/json' \
            -d '{"unload_models": true, "free_memory": true}' >/dev/null
        echo "comfy: models unloaded"
    }
    free_tts() {  # its tmux session ends, and its CUDA context a moment after
        tmux has-session -t "=${tts}" 2>/dev/null || return 0
        tmux kill-session -t "=${tts}"
        for _ in $(seq 1 30); do tmux has-session -t "=${tts}" 2>/dev/null || break; sleep 1; done
        sleep 3
        echo "tts: stopped"
    }
    [[ "$to" == llm ]] || free_llm
    [[ "$to" == comfy ]] || free_comfy
    [[ "$to" == tts ]] || free_tts
    echo "ai_box_gpu: the GPU is free for ${to}"
  offers.sh: |
    #!/usr/bin/env bash
    # offers — what this box serves to the other hosts, for reporting (kind=offer): one JSON
    # object per line, `localhost` meaning this host (reporting puts in the address the others
    # reach it by). With a decree-go-rest in front of the host's .decree, `lease` is where to
    # ask for the card: POST <lease>/<client>; the lease's status is GET <api>/gpu/lease/<id>,
    # and POST <api>/gpu/lease/<id>/release gives it back. TTS is started, not leased.
    set -euo pipefail
    llm="${AI_BOX_LLAMA_URL:-http://localhost:8080}"
    comfy="${AI_BOX_COMFYUI_URL:-http://localhost:8188}"
    tts="${AI_BOX_TTS_URL:-http://localhost:8000}"
    rest=.decree/decree-go-rest.yml api=""
    if [[ -f "$rest" ]] && grep -q 'path: /gpu/{mode}/{client}' "$rest"; then
        api="http://localhost:$(sed -n 's/^listen:[[:space:]]*[^#]*:\([0-9][0-9]*\).*/\1/p' "$rest" | head -n 1)"
    fi
    offer() {  # <service> <url> [<key> <value>]...
        local s="{\"service\":\"$1\",\"url\":\"$2\""; shift 2
        while [[ $# -gt 1 ]]; do s="${s},\"$1\":\"$2\""; shift 2; done
        echo "${s}}"
    }
    # AI_BOX_SERVICES: what this box offers (default all three). Taking one out moves it off
    # this box: its next report drops it, leases held now run out, and new ones go elsewhere.
    on() { [[ ",${AI_BOX_SERVICES:-llm,comfy,tts}," == *",$1,"* ]]; }
    if [[ -n "$api" ]]; then
        if on llm; then offer llm "${llm}/v1" lease "${api}/gpu/llm" api "$api"; fi
        if on comfy; then offer comfy "$comfy" lease "${api}/gpu/comfy" api "$api"; fi
        if on tts; then offer tts "$tts" start "${api}/startTTS" stop "${api}/endTTS" api "$api"; fi
    else
        if on llm; then offer llm "${llm}/v1"; fi
        if on comfy; then offer comfy "$comfy"; fi
    fi
  requirements: |
    # What ai_box_gpu's scripts need beyond decree, checked by decree_infra's `run.sh check`.
    # kind    name    version   source
    command   bash
    command   flock
    command   jq
    command   curl
    command   tmux
x-exist-endpoints:
  # Ask for the card, from another host: the answer's id is the lease. Ten minutes, renewed
  # by its holder while it works, so a holder that dies frees the card soon after.
  - path: /gpu/{mode}/{client}
    patterns: {mode: "llm|comfy|tts", client: "[a-z0-9_-]{1,40}"}
    body: optional
    message:
      machine: ai_box_gpu
      params: {resource: gpu, mode: "{{mode}}", holder: "{{client}}", duration: 10m}
  # The lease's status: state waiting, swapping, granted, held, released, expired...
  - path: /gpu/lease/{id}
    action: read
    patterns: {id: "[0-9A-Za-z._-]{1,80}"}
    read: {machine: ai_box_gpu, path: "status/leases/{{id}}.json"}
  # Give it back, or keep it for its duration again.
  - path: /gpu/lease/{id}/{answer}
    action: reply
    patterns: {id: "[0-9A-Za-z._-]{1,80}", answer: "release|renew"}
    reply: {to: "{{id}}", event: "{{answer}}"}
  # The card: its mode, holders and line.
  - path: /gpu
    action: read
    read: {machine: ai_box_gpu, path: status/resources/gpu.json}
---
# ai_box_gpu

The card on a separate AI box, as decree's `decree_lease` with one resource, `gpu`, in mode
`llm`, `comfy` or `tts`. A lease in one mode stops the others first: the llama.cpp router
unloads its models, ComfyUI finishes its queue and unloads, the TTS session ends. It runs in
the host daemon, so it reaches the services on `localhost` and TTS's tmux session directly.

With a decree-go-rest in front of the host's `.decree`, another host asks over HTTP:
`POST /gpu/<mode>/<client>` (the answer's `id` is the lease), `GET /gpu/lease/<id>` until its
`state` is `granted` or `held`, then `POST /gpu/lease/<id>/release`; `GET /gpu` is the card.
`scripts/offers.sh` tells the others all this through `reporting` (`./existential.sh run peers`).

Ask on the host with
`decree emit --machine ai_box_gpu --param resource=gpu --param mode=<mode> --param holder=<who>`,
and give it back with `decree reply <lease id> release`. Only work that asks takes part: a
model call or a ComfyUI prompt that does not ask uses the card anyway.

Linux only (decree_lease needs `flock`). Set `AI_BOX_LLAMA_URL` and `AI_BOX_COMFYUI_URL` in
`.decree/.env` when they are not on `localhost:8080` and `localhost:8188`.
