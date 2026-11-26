---
name: fleet
x-exist-project: automation
x-exist-lib:
  fleet.sh: |
    #!/usr/bin/env bash
    # fleet.sh — a GPU service another host offers, found by asking the controller and used
    # under that host's lease.
    #
    # Sourced, never run. Every host reports what it offers (kind="offer") to the Loki its
    # controller names; a GPU box offers llm, comfy and tts, each with the address of its
    # lease (decree-go-rest: POST to ask, GET the status, POST .../release). Here:
    #
    #   fleet_use <service>   sets FLEET_URL to where the service is now, holding its lease;
    #                         returns 3 when the fleet has none (use your own address), 1
    #                         when no host that offers it would lease it
    #   fleet_done <service>  this call is over
    #
    # The lease is this container's, shared by every call: the first fleet_use asks for it
    # and starts a keeper, later ones reuse it, and the keeper gives it back once no call
    # has been in flight for FLEET_IDLE seconds (default 5) and, for comfy, ComfyUI's queue
    # is empty. A burst of calls is one lease. Each new lease asks the controller again, so
    # a service moved to another host is found there on the next one.
    #
    #   fleet_offers [<service>]          every host's latest offers, one JSON object a line
    #   fleet_lease <offer> <holder>      ask, wait until held (FLEET_WAIT s, default 2400), print the id
    #   fleet_answer <offer> <id> <release|renew>
    #
    # Env: EXIST_FLEET_SECRET (every host's decree-go-rest takes it) and EXIST_CONTROLLER (its
    # Loki, on :43100, holds the offers; the stack sets EXIST_FLEET_LOKI instead), FLEET_HOLDER
    # (default this host's name), FLEET_STATE_DIR.
    # Needs curl and jq. bash 3.2: the host's `./existential.sh run peers` sources it too.

    FLEET_IDLE="${FLEET_IDLE:-5}"
    FLEET_STATE_DIR="${FLEET_STATE_DIR:-${TMPDIR:-/tmp}/fleet}"

    _fleet_loki() { echo "${EXIST_FLEET_LOKI:-${EXIST_CONTROLLER:+http://${EXIST_CONTROLLER}:43100}}"; }
    fleet_on() { [ -n "${EXIST_FLEET_SECRET:-}" ] && [ -n "$(_fleet_loki)" ]; }

    fleet_offers() {
        local out
        out="$(curl -fsSG --max-time 15 "$(_fleet_loki)/loki/api/v1/query_range" \
            --data-urlencode 'query={job="exist", kind="offer"}' \
            --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
            --data-urlencode direction=backward --data-urlencode limit=2000)" || return 1
        jq -c --arg s "${1:-}" '[.data.result[] | .stream.host as $h | .values[]
            | {h: $h, t: .[0], o: (.[1] | fromjson? // empty)}]
            | group_by(.h) | map((max_by(.t).t[0:-9]) as $last | .[] | select(.t[0:-9] == $last) | {host: .h} + .o)
            | sort_by(.host, .service) | .[] | select($s == "" or .service == $s)' <<<"$out"
    }

    _fleet_auth() { printf 'Authorization: Bearer %s' "$EXIST_FLEET_SECRET"; }

    fleet_lease() {
        local offer="$1" holder="$2" url api id state waited=0
        url="$(jq -r '.lease // empty' <<<"$offer")"; api="$(jq -r '.api // empty' <<<"$offer")"
        [ -n "$url" ] && [ -n "$api" ] || return 1
        id="$(curl -fsS --max-time 15 -X POST -H "$(_fleet_auth)" "${url}/${holder}" | jq -r '.id // empty')" || return 1
        [ -n "$id" ] || return 1
        echo "fleet: asked $(jq -r .host <<<"$offer") for its $(jq -r .service <<<"$offer"), lease ${id}" >&2
        while [ "$waited" -lt "${FLEET_WAIT:-2400}" ]; do
            state="$(curl -fsS --max-time 10 -H "$(_fleet_auth)" "${api}/gpu/lease/${id}" 2>/dev/null | jq -r '.state // empty' || true)"
            case "$state" in
                granted|held) echo "$id"; return 0 ;;
                released|expired|failed|cancelled) echo "fleet: lease ${id} ended: ${state}" >&2; return 1 ;;
            esac
            sleep 2; waited=$((waited + 2))
        done
        fleet_answer "$offer" "$id" release
        echo "fleet: lease ${id} not granted within ${FLEET_WAIT:-2400}s" >&2
        return 1
    }

    fleet_answer() {
        curl -fsS --max-time 15 -X POST -H "$(_fleet_auth)" \
            "$(jq -r '.api' <<<"$1")/gpu/lease/${2}/${3}" >/dev/null 2>&1
    }

    # A lock per service: a folder holding its owner's pid, taken over when that pid is gone.
    _fleet_lock() {
        until mkdir "$1/lock" 2>/dev/null; do
            kill -0 "$(cat "$1/lock/pid" 2>/dev/null || echo 0)" 2>/dev/null || rm -rf "$1/lock"
            sleep 0.2
        done
        echo $$ > "$1/lock/pid"
    }
    _fleet_unlock() { rm -rf "$1/lock"; }

    # shellcheck disable=SC2034  # FLEET_URL is what the caller reads
    fleet_use() {
        local svc="$1" d offer id holder
        FLEET_URL="" FLEET_TOKEN=""
        fleet_on || return 3
        d="${FLEET_STATE_DIR}/${svc}"; mkdir -p "$d/inflight"
        _fleet_lock "$d"
        # The keeper beats every second; a lease whose keeper stopped beating is not reused.
        if [ ! -s "$d/id" ] || [ $(( $(date +%s) - $(cat "$d/beat" 2>/dev/null || echo 0) )) -gt 3 ]; then
            rm -f "$d/id" "$d/offer" "$d/url"
            holder="$(printf '%s-%s' "${FLEET_HOLDER:-$(hostname -s 2>/dev/null || hostname)}" "$svc" \
                | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_\n-' '-' | cut -c1-40)"
            id=""
            while IFS= read -r offer; do
                [ -n "$offer" ] || continue
                if id="$(fleet_lease "$offer" "$holder")"; then break; fi
                id=""
            done < <(fleet_offers "$svc" 2>/dev/null || true)
            if [ -z "$id" ]; then
                _fleet_unlock "$d"
                fleet_offers "$svc" 2>/dev/null | grep -q . && return 1
                return 3
            fi
            printf '%s\n' "$id" > "$d/id"; printf '%s\n' "$offer" > "$d/offer"
            jq -r .url <<<"$offer" > "$d/url"; date +%s > "$d/last"; date +%s > "$d/beat"
            # Its own session, so the run that asked can end without taking it along.
            export FLEET_STATE_DIR FLEET_IDLE EXIST_FLEET_SECRET EXIST_FLEET_LOKI EXIST_CONTROLLER
            if command -v setsid >/dev/null 2>&1; then
                setsid bash -c "$(declare -f _fleet_loki fleet_offers _fleet_auth fleet_answer _fleet_lock _fleet_unlock fleet_keeper); fleet_keeper '$svc'" \
                    </dev/null >/dev/null 2>&1 &
            else
                ( fleet_keeper "$svc" ) </dev/null >/dev/null 2>&1 &
            fi
        fi
        FLEET_URL="$(cat "$d/url")"
        FLEET_TOKEN="$d/inflight/$$.${RANDOM}"
        : > "$FLEET_TOKEN"
        _fleet_unlock "$d"
    }

    fleet_done() {
        [ -n "${FLEET_TOKEN:-}" ] || return 0
        rm -f "$FLEET_TOKEN"
        date +%s > "${FLEET_STATE_DIR}/${1}/last"
        FLEET_TOKEN=""
    }

    # fleet_keeper <service> — holds the lease while calls come, renews it before it ends,
    # and gives it back FLEET_IDLE seconds after the last one.
    fleet_keeper() {
        local svc="$1" d="${FLEET_STATE_DIR}/${1}" offer id t busy now n=0 st exp
        offer="$(cat "$d/offer")"; id="$(cat "$d/id")"
        while :; do
            sleep 1; n=$((n + 1))
            date +%s > "$d/beat"
            busy=""
            for t in "$d"/inflight/*; do
                [ -e "$t" ] || continue
                t="${t##*/}"
                if kill -0 "${t%%.*}" 2>/dev/null; then busy=1; else rm -f "$d/inflight/$t"; fi
            done
            if [ -z "$busy" ] && [ "$svc" = comfy ] &&
                curl -fsS --max-time 5 "$(cat "$d/url")/queue" 2>/dev/null |
                    jq -e '(.queue_running + .queue_pending) | length > 0' >/dev/null 2>&1; then
                busy=1; date +%s > "$d/last"
            fi
            now="$(date +%s)"
            if [ -z "$busy" ] && [ $((now - $(cat "$d/last" 2>/dev/null || echo 0))) -ge "${FLEET_IDLE:-5}" ]; then
                _fleet_lock "$d"
                if ! ls "$d"/inflight/* >/dev/null 2>&1; then
                    fleet_answer "$offer" "$id" release
                    rm -f "$d/id" "$d/offer" "$d/url" "$d/beat"
                    _fleet_unlock "$d"; return 0
                fi
                _fleet_unlock "$d"
            fi
            # Every 30 s: still held? Renew it in its last two minutes.
            if [ $((n % 30)) -eq 0 ]; then
                st="$(curl -fsS --max-time 10 -H "$(_fleet_auth)" "$(jq -r .api <<<"$offer")/gpu/lease/${id}" 2>/dev/null || true)"
                case "$(jq -r '.state // empty' <<<"$st" 2>/dev/null)" in
                    granted|held)
                        exp="$(jq -r '.expires // empty' <<<"$st" | cut -c1-19)"
                        exp="$(date -u -d "$exp" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%S' "$exp" +%s 2>/dev/null || echo 0)"
                        [ "$exp" -eq 0 ] || [ $((exp - now)) -gt 120 ] || fleet_answer "$offer" "$id" renew ;;
                    "") ;;
                    *) _fleet_lock "$d"; rm -f "$d/id" "$d/offer" "$d/url" "$d/beat"; _fleet_unlock "$d"; return 0 ;;
                esac
            fi
        done
    }
---
# fleet

A GPU service another host offers, found by asking the controller and used under that host's lease:
fleet_use and fleet_done (.decree/lib/fleet.sh). model_chat, pi_run and comfy use it. See
/docs/hosting/controller-and-workers#peers-what-the-other-hosts-offer.
