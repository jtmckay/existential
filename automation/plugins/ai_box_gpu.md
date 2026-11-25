---
name: ai_box_gpu
extends: decree_lease
x-exist-project: host
scripts:
  resources: |
    # A separate AI box's one card: one GPU-heavy service at a time.
    #   name  max_lease  linger  max_wait  modes         holders
    # Modes: llm (the llama.cpp router), comfy (ComfyUI), tts (the TTS server) and strata
    # (Strata); the swap starts the last two. Up to four leases share the card in one mode;
    # another mode waits for all of them.
    gpu     4h         5s      30m       llm,comfy,tts,strata  4
  swap/gpu.sh: |
    #!/usr/bin/env bash
    # gpu.sh <from> <to>: free the card for <to> by stopping every other GPU user. <to> loads
    # on demand (llama.cpp, ComfyUI) or, for tts and strata, is started here: each loads its
    # model when it starts, so the lease owns it, and the lease is granted once it answers.
    # A service that does not answer holds nothing. Addresses and the session name: .decree/.env.
    set -euo pipefail
    to="$2"
    llm="${AI_BOX_LLAMA_URL:-http://localhost:8080}"
    comfy="${AI_BOX_COMFYUI_URL:-http://localhost:8188}"
    tts="${AI_BOX_TTS_SESSION:-tts}"
    tts_url="${AI_BOX_TTS_URL:-http://localhost:8000}"
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
    # TTS: AI_BOX_TTS_COMMAND in a tmux session, run again if it exits: the swap runs only
    # when the mode changes, so nothing else would.
    start_tts() {
        : "${AI_BOX_TTS_COMMAND:?tts: set AI_BOX_TTS_COMMAND in .decree/.env, the command that runs your TTS server}"
        tmux has-session -t "=${tts}" 2>/dev/null ||
            tmux new-session -d -s "$tts" "cd ~ && while :; do ${AI_BOX_TTS_COMMAND}; sleep 5; done"
        # Held once it answers: a first start downloads the model.
        until [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$tts_url" 2>/dev/null)" != 000 ]]; do
            tmux has-session -t "=${tts}" 2>/dev/null || { echo "tts: the session ended while loading (tmux attach -t ${tts})" >&2; return 1; }
            sleep 5
        done
        echo "tts: serving"
    }
    free_tts() {  # its tmux session ends, and its CUDA context a moment after
        tmux has-session -t "=${tts}" 2>/dev/null || return 0
        tmux kill-session -t "=${tts}"
        for _ in $(seq 1 30); do tmux has-session -t "=${tts}" 2>/dev/null || break; sleep 1; done
        sleep 3
        echo "tts: stopped"
    }
    # Strata: the ai/strata service's image and model pack, in a container of the lease's own
    # (not compose, whose `up -d` would start it again behind the lease). Its downloads are
    # volumes/strata_cache, the service's, so a pack is fetched once.
    engine="$(command -v podman || command -v docker || true)"
    strata="${AI_BOX_STRATA_CONTAINER:-ai-box-strata}"
    strata_key="$(sed -n 's/^EXIST_MODEL_API_KEY=//p' .env.shared 2>/dev/null | head -n 1)"
    strata_url="http://127.0.0.1:${AI_BOX_STRATA_PORT:-8081}"
    strata_up() { [[ -n "$engine" ]] && [[ -n "$("$engine" ps -q --filter "name=^${strata}\$" 2>/dev/null)" ]]; }
    free_strata() {
        strata_up || return 0
        "$engine" stop -t 120 "$strata" >/dev/null
        "$engine" rm -f "$strata" >/dev/null 2>&1 || true
        echo "strata: stopped"
    }
    start_strata() {
        local image gpu
        [[ -n "$engine" ]] || { echo "strata: no podman or docker here" >&2; return 1; }
        [[ -n "${AI_BOX_STRATA_FAMILY:-}" ]] || { echo "strata: set AI_BOX_STRATA_FAMILY (and AI_BOX_STRATA_MODEL) in .decree/.env" >&2; return 1; }
        if ! strata_up; then
            image="${AI_BOX_STRATA_IMAGE:-$(sed -n 's/^ *image: *\(ghcr\.io\/niko1221\/strata:[^ ]*-cuda[0-9]*\).*/\1/p' ai/strata/docker-compose.exist.yml | head -n 1)}"
            # podman: CDI for the card, and its bridge network, as compose uses (a plain rootless
            # run's pasta resets the IPv6 that localhost and the hostname resolve to first).
            gpu=(--gpus all); [[ "$engine" == *podman ]] && gpu=(--device nvidia.com/gpu=all --network podman)
            mkdir -p volumes/strata_cache
            # Its RAM cap, and the engine told it too, so it plans within it: Strata fills the RAM
            # it is given with cached experts. 64g serves the full context at full speed on a 24 GB card.
            mem="${AI_BOX_STRATA_MEMORY:-64g}" mib=""
            case "$mem" in *g|*G) mib=$(( ${mem%[gG]} * 1024 )) ;; *m|*M) mib="${mem%[mM]}" ;; esac
            "$engine" rm -f "$strata" >/dev/null 2>&1 || true
            # Restarted if it crashes: the swap runs only when the mode changes, so nothing else would.
            "$engine" run -d --restart on-failure --name "$strata" "${gpu[@]}" --security-opt label=disable \
                --ulimit memlock=-1:-1 --shm-size 2g --memory "$mem" ${mib:+-e STRATA_MEMORY_LIMIT_MIB="$mib"} \
                -p "${AI_BOX_STRATA_PORT:-8081}:8080" -v "$(pwd)/volumes/strata_cache:/data" \
                -e FAMILY="$AI_BOX_STRATA_FAMILY" -e MODEL="${AI_BOX_STRATA_MODEL:-}" -e API_KEY="$strata_key" \
                -e CONTEXT="${AI_BOX_STRATA_CONTEXT:-65536}" "$image" >/dev/null
            echo "strata: started ${image}"
        fi
        # Held once it serves a model: a load takes minutes, a first download much longer.
        until curl -fsS --max-time 10 -H "Authorization: Bearer ${strata_key}" "${strata_url}/v1/models" 2>/dev/null |
                jq -e '.data | length > 0' >/dev/null 2>&1; do
            strata_up || { echo "strata: the container stopped while loading (${engine##*/} logs ${strata})" >&2; return 1; }
            sleep 5
        done
        # What it serves, for offers.sh while it is stopped.
        curl -fsS --max-time 10 -H "Authorization: Bearer ${strata_key}" "${strata_url}/v1/models" \
            > .decree/machines/ai_box_gpu/state/strata-models.json || true
        echo "strata: serving"
    }
    [[ "$to" == llm ]] || free_llm
    [[ "$to" == comfy ]] || free_comfy
    [[ "$to" == tts ]] || free_tts
    [[ "$to" == strata ]] || free_strata
    [[ "$to" != strata ]] || start_strata
    [[ "$to" != tts ]] || start_tts
    echo "ai_box_gpu: the GPU is free for ${to}"
  offers.sh: |
    #!/usr/bin/env bash
    # offers — what this box serves to the other hosts, for reporting (kind=offer): one JSON
    # object per line, `localhost` meaning this host (reporting puts in the address the others
    # reach it by). With a decree-go-rest in front of the host's .decree, `lease` is where to
    # ask for the card: POST <lease>/<client>; the lease's status is GET <api>/gpu/lease/<id>,
    # and POST <api>/gpu/lease/<id>/release gives it back. llm and strata carry `models`, each
    # model's id and context, read without loading anything.
    set -euo pipefail
    llm="${AI_BOX_LLAMA_URL:-http://localhost:8080}"
    comfy="${AI_BOX_COMFYUI_URL:-http://localhost:8188}"
    tts="${AI_BOX_TTS_URL:-http://localhost:8000}"
    strata="http://localhost:${AI_BOX_STRATA_PORT:-8081}"
    rest=.decree/decree-go-rest.yml api=""
    if [[ -f "$rest" ]] && grep -q 'path: /gpu/{mode}/{client}' "$rest"; then
        api="http://localhost:$(sed -n 's/^listen:[[:space:]]*[^#]*:\([0-9][0-9]*\).*/\1/p' "$rest" | head -n 1)"
    fi
    offer() {  # <service> <url> <models JSON, or ""> [<key> <value>]...
        local s="{\"service\":\"$1\",\"url\":\"$2\""
        [[ -z "$3" ]] || s="${s},\"models\":$3"
        shift 3
        while [[ $# -gt 1 ]]; do s="${s},\"$1\":\"$2\""; shift 2; done
        echo "${s}}"
    }
    # llama.cpp's router lists every model it can load, with the --ctx-size each starts with.
    llm_models() {
        curl -fsS --max-time 5 "${llm}/v1/models" 2>/dev/null | jq -c '[.data[] | {id,
            context: ((.status.args // []) as $a | ($a | index("--ctx-size")) as $i
                | if $i then ($a[$i + 1] | tonumber) else null end)}]' 2>/dev/null || echo '[]'
    }
    # Strata: what it served when the lease last started it, with the context it is set to.
    strata_models() {
        jq -c --argjson c "${AI_BOX_STRATA_CONTEXT:-65536}" '[.data[] | {id, context: $c}]' \
            .decree/machines/ai_box_gpu/state/strata-models.json 2>/dev/null || echo '[]'
    }
    # AI_BOX_SERVICES: what this box offers (default llm,comfy,tts; add strata to offer it,
    # with AI_BOX_STRATA_FAMILY set). Taking one out moves it off
    # this box: its next report drops it, leases held now run out, and new ones go elsewhere.
    on() { [[ ",${AI_BOX_SERVICES:-llm,comfy,tts}," == *",$1,"* ]]; }
    if [[ -n "$api" ]]; then
        if on llm; then offer llm "${llm}/v1" "$(llm_models)" lease "${api}/gpu/llm" api "$api"; fi
        if on comfy; then offer comfy "$comfy" "" lease "${api}/gpu/comfy" api "$api"; fi
        if on tts; then offer tts "$tts" "" lease "${api}/gpu/tts" api "$api"; fi
        if on strata; then offer strata "${strata}/v1" "$(strata_models)" lease "${api}/gpu/strata" api "$api"; fi
    else
        if on llm; then offer llm "${llm}/v1" "$(llm_models)"; fi
        if on comfy; then offer comfy "$comfy" ""; fi
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
    patterns: {mode: "llm|comfy|tts|strata", client: "[a-z0-9_-]{1,40}"}
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
`llm`, `comfy`, `tts` or `strata`. A lease in one mode stops the others first: the llama.cpp
router unloads its models, ComfyUI finishes its queue and unloads, the TTS session ends,
Strata's container stops. A `tts` or `strata` lease starts its server and is granted once it
answers. It runs in the host daemon, so it reaches the services on `localhost` directly.

With a decree-go-rest in front of the host's `.decree`, another host asks over HTTP:
`POST /gpu/<mode>/<client>` (the answer's `id` is the lease), `GET /gpu/lease/<id>` until its
`state` is `granted` or `held`, then `POST /gpu/lease/<id>/release`; `GET /gpu` is the card.
`scripts/offers.sh` tells the others all this through `reporting` (`./existential.sh run peers`).

Ask on the host with
`decree emit --machine ai_box_gpu --param resource=gpu --param mode=<mode> --param holder=<who>`,
and give it back with `decree reply <lease id> release`. Only work that asks takes part: a
model call or a ComfyUI prompt that does not ask uses the card anyway.

Linux only (decree_lease needs `flock`). Set `AI_BOX_LLAMA_URL`, `AI_BOX_COMFYUI_URL` and
`AI_BOX_TTS_URL` in `.decree/.env` when they are not on `localhost:8080`, `:8188` and `:8000`,
and `AI_BOX_TTS_COMMAND` to the command that runs the TTS server.
