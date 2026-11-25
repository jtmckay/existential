---
name: ai_box_tts
x-exist-project: host
needs:
  - ai_box_gpu
machine:
  description: Start or stop the TTS server on a separate AI box. Start takes the GPU first (an ai_box_gpu lease in mode tts) and then starts AI_BOX_TTS_COMMAND in a tmux session; stop ends the session and gives the lease back.
  data:
    action: {type: string, default: start, enum: [start, stop]}
  initial: route
  states:
    route:
      invoke:
        check: {data: action, equals: start}
      transitions: {"true": lease, "false": stop}
    lease:
      # Another mode may hold the card for up to max_wait + max_lease; the timeout covers a slice.
      emits: [ai_box_gpu]
      invoke:
        script: {name: lease, timeout: 40m}
      transitions: {done: start}
    start:
      invoke: start
      transitions: {done: done}
    stop:
      invoke: stop
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  lease.sh: |
    #!/usr/bin/env bash
    # lease — the card in mode tts, held by `tts`: a tts lease already waiting or holding it
    # is reused, else one is asked for. Waits until it is granted.
    set -euo pipefail
    status=.decree/machines/ai_box_gpu/state/status/leases
    live() {
        [[ -d "$status" ]] || return 0
        jq -r 'select(.holder == "tts" and (.state | IN("waiting", "swapping", "granted", "held"))) | .run' \
            "$status"/*.json 2>/dev/null | head -n 1 || true
    }
    id="$(live)"
    if [[ -z "$id" ]]; then
        id="$(echo "TTS" | "${DECREE:-decree}" emit --machine ai_box_gpu \
            --param resource=gpu --param mode=tts --param holder=tts)"
        echo "ai_box_tts: asked for the GPU, lease ${id}"
    else
        echo "ai_box_tts: lease ${id} already asked for"
    fi
    while :; do
        state="$(jq -r .state "${status}/${id}.json" 2>/dev/null || echo waiting)"
        case "$state" in
            granted|held) echo "ai_box_tts: lease ${id} ${state}"; exit 0 ;;
            released|expired|failed|cancelled) echo "ai_box_tts: lease ${id} ended: ${state}" >&2; exit 1 ;;
        esac
        sleep 2
    done
  start.sh: |
    #!/usr/bin/env bash
    # start — AI_BOX_TTS_COMMAND (.decree/.env) in the tmux session AI_BOX_TTS_SESSION
    # (default tts), with tmx -d: nothing to do when it already runs.
    set -euo pipefail
    : "${AI_BOX_TTS_COMMAND:?ai_box_tts: set AI_BOX_TTS_COMMAND in .decree/.env, the command that runs your TTS server}"
    session="${AI_BOX_TTS_SESSION:-tts}"
    # shellcheck source=/dev/null
    . "$(pwd)/services/automation/decree/tmx.sh"
    if tmux has-session -t "=${session}" 2>/dev/null; then echo "ai_box_tts: ${session} already running"; exit 0; fi
    tmx -d "$session" "cd ~ && exec ${AI_BOX_TTS_COMMAND}"
    # A bad flag or a missing package ends the session within seconds.
    sleep 5
    tmux has-session -t "=${session}" 2>/dev/null ||
        { echo "ai_box_tts: ${session} exited at once; run AI_BOX_TTS_COMMAND by hand to see why" >&2; exit 1; }
    echo "ai_box_tts: ${session} started; watch it with: tmx ${session}"
  stop.sh: |
    #!/usr/bin/env bash
    # stop — end the session, then give back every tts lease still waiting or holding the card.
    set -euo pipefail
    session="${AI_BOX_TTS_SESSION:-tts}"
    if tmux has-session -t "=${session}" 2>/dev/null; then
        tmux kill-session -t "=${session}"; echo "ai_box_tts: ${session} stopped"
    else
        echo "ai_box_tts: ${session} not running"
    fi
    status=.decree/machines/ai_box_gpu/state/status/leases
    [[ -d "$status" ]] || exit 0
    ids="$(jq -r 'select(.holder == "tts" and (.state | IN("waiting", "swapping", "granted", "held"))) | .run' \
        "$status"/*.json 2>/dev/null || true)"
    for id in $ids; do
        if "${DECREE:-decree}" reply "$id" release -m ai_box_tts 2>/dev/null; then
            echo "ai_box_tts: released lease ${id}"
        else
            # The lease's run is in a step, not waiting: queue the reply, delivered once it waits.
            f=".decree/inbox/ai-box-tts-release-${id}"
            printf -- '---\nto: %s\nevent: release\n---\nai_box_tts stop\n' "$id" > "${f}.tmp"
            mv "${f}.tmp" "${f}.md"
            echo "ai_box_tts: release queued for lease ${id}"
        fi
    done
x-exist-endpoints:
  - path: /startTTS
    body: none
    message:
      machine: ai_box_tts
      params: {action: start}
  - path: /endTTS
    body: none
    message:
      machine: ai_box_tts
      params: {action: stop}
---
# ai_box_tts

TTS on a separate AI box, started and stopped on demand: `start` takes the card from llama.cpp
and ComfyUI first (an `ai_box_gpu` lease in mode `tts`), `stop` ends the session and gives the
card back. On the host:

    decree emit --machine ai_box_tts --param action=start </dev/null
    decree emit --machine ai_box_tts --param action=stop </dev/null

With a `.decree/decree-go-rest.yml` on the host, it also answers `POST /startTTS` and `/endTTS`.
