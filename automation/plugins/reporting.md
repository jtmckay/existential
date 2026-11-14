---
machine: plugin
automation: reporting
chart:
  description: Report this host to the Loki its controller names - free disk space, CPU, RAM and VRAM use, the decree machines, plugins and crons installed, the containers running - and keep alloy shipping every decree run there live.
  store:
    loki: The Loki push address the controller last gave, used while it cannot be reached. report reads and writes it.
    alloy-loki: The Loki address the running alloy was started with; a new one restarts it. report reads and writes it.
    alloy: alloy's own state, its read position in each run's files. alloy writes it.
    cpu: The /proc/stat CPU counters at the last report, so the next one averages over the time between. report reads and writes it.
  initial: report
  states:
    report:
      invoke: report
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  report: |
    #!/usr/bin/env bash
    # report — this host, to the Loki its controller names.
    #
    # Runs in the host project (host/.decree), so the repo is one up and every
    # decree project on the box is in reach. With EXIST_CONTROLLER in .env.shared it
    # asks that controller at http://<controller>:4480, which serves host/exist.json
    # over the tailnet; blank, this host is the controller and reads that file. The
    # answer is kept in $DECREE_STORE/loki for when the controller is away. No
    # answer is not a failure: nothing is sent and the run ends done.
    #
    # One push, labelled {job="exist", host, kind}: kind=disk per disk, kind=load
    # (CPU, RAM, VRAM) once, kind=machine per installed decree machine, kind=plugin
    # per installed plugin, kind=cron per active cron, kind=container per running
    # container. Each run
    # is alloy's, below, as {job="decree"} and {job="decree_script"}.
    #
    # On the host, so bash 3.2 and BSD tools on a Mac: no jq, no date +%N.
    set -euo pipefail
    repo="$(cd .. && pwd)"
    store="${DECREE_STORE:-.decree/store/reporting}"; mkdir -p "$store"
    env_get() { sed -n "s/^$1=//p" "${repo}/.env.shared" 2>/dev/null | head -1; }
    loki_of() { sed -n 's/.*"loki"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'; }

    ctl="$(env_get EXIST_CONTROLLER)"
    if [[ -n "$ctl" ]]; then
        loki="$(curl -fsS --max-time 5 "http://${ctl}:4480/" 2>/dev/null | loki_of || true)"
    else
        loki="$(loki_of < "${repo}/host/exist.json" 2>/dev/null || true)"
    fi
    if [[ -n "$loki" ]]; then printf '%s\n' "$loki" > "${store}/loki"
    else loki="$(cat "${store}/loki" 2>/dev/null || true)"; fi
    [[ -n "$loki" ]] || { echo "reporting: no Loki named yet (EXIST_REPORTING_URL on the controller, or Loki on there), so nothing is sent"; exit 0; }

    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

    # The disks are / and each mount under /mnt (/var/mnt on an atomic host). On
    # ostree, / is a read-only composefs image and the disk under it is /sysroot.
    root=/; [[ -d /sysroot/ostree ]] && root=/sysroot
    { df -Pk "$root" /mnt/* 2>/dev/null || true; } | awk -v root="$root" 'NR > 1 {
        m = $6; for (i = 7; i <= NF; i++) m = m " " $i
        if (m == root) m = "/"
        if ((m != "/" && m !~ "^(/var)?/mnt/") || seen[m]++) next
        printf "{\"mount\":\"%s\",\"device\":\"%s\",\"size_kb\":%s,\"avail_kb\":%s}\n", m, $1, $2, $4 }' > "${tmp}/disk"

    # CPU % is the average since the last report (/proc/stat, kept in the store);
    # a Mac, or a first report, takes a one-second sample. RAM used is total less
    # what the kernel says is available. VRAM is every GPU's, summed, when any.
    if [[ -r /proc/stat ]]; then
        cur="$(awk '/^cpu /{ t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6 }' /proc/stat)"
        prev="$(cat "${store}/cpu" 2>/dev/null || true)"
        if [[ -z "$prev" ]]; then
            prev="$cur"; sleep 1
            cur="$(awk '/^cpu /{ t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6 }' /proc/stat)"
        fi
        printf '%s\n' "$cur" > "${store}/cpu"
        cpu="$(echo "$prev $cur" | awk '{ dt = $3 - $1; printf "%.1f", (dt > 0 ? 100 * (1 - ($4 - $2) / dt) : 0) }')"
        mem="$(awk '/^MemTotal:/{ t = $2 } /^MemAvailable:/{ a = $2 } END { print t - a, t }' /proc/meminfo)"
    else
        cpu="$(top -l 2 -n 0 -s 1 | awk '/^CPU usage/{ v = $7 } END { sub("%", "", v); printf "%.1f", 100 - v }')"
        mem="$(vm_stat | awk -v t="$(sysctl -n hw.memsize)" '/page size of/{ p = $8 }
            /^Pages (wired down|active|occupied by compressor):/{ gsub("\\.", "", $NF); u += $NF }
            END { printf "%d %d\n", u * p / 1024, t / 1024 }')"
    fi
    vram=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        vram="$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null \
            | awk -F', *' '{ u += $1; t += $2 } END { if (NR) printf ",\"vram_used_mb\":%d,\"vram_total_mb\":%d", u, t }')"
    elif ls /sys/class/drm/card*/device/mem_info_vram_total >/dev/null 2>&1; then
        vram="$(for d in /sys/class/drm/card*/device; do if [[ -r "$d/mem_info_vram_total" ]]; then echo "$(cat "$d/mem_info_vram_used") $(cat "$d/mem_info_vram_total")"; fi; done \
            | awk '{ u += $1; t += $2 } END { printf ",\"vram_used_mb\":%d,\"vram_total_mb\":%d", u / 1048576, t / 1048576 }')"
    fi
    echo "$mem" | awk -v c="$cpu" -v v="$vram" '{ printf "{\"cpu_pct\":%s,\"mem_used_kb\":%d,\"mem_total_kb\":%d%s}\n", c, $1, $2, v }' > "${tmp}/load"

    # Each project's machines, and its plugins: what plugin sync installed there
    # (applied/plugins/), the ones turned on and the ones they need.
    : > "${tmp}/machine"; : > "${tmp}/plugin"; : > "${tmp}/cron"
    for p in automation:volumes/workspace_data/.decree automation-backup:services/automation-backup host:host/.decree; do
        name="${p%%:*}" dir="${repo}/${p#*:}"
        [[ -d "$dir" ]] || continue
        for m in "$dir"/machines/*.yml; do
            [[ -f "$m" ]] || continue
            printf '{"project":"%s","machine":"%s"}\n' "$name" "$(basename "$m" .yml)" >> "${tmp}/machine"
        done
        for m in "$dir"/applied/plugins/*.md; do
            [[ -f "$m" ]] || continue
            printf '{"project":"%s","plugin":"%s"}\n' "$name" "$(basename "$m" .md)" >> "${tmp}/plugin"
        done
        # Each active cron (cron/, what the daemon fires): its schedule and machine.
        for m in "$dir"/cron/*.md; do
            [[ -f "$m" ]] || continue
            awk -v p="$name" -v n="$(basename "$m" .md)" '
                NR == 1 && /^---/ { fm = 1; next }
                fm && /^---/ { exit }
                fm && /^cron:/ { sub(/^cron:[[:space:]]*/, ""); gsub(/["\047]/, ""); c = $0 }
                fm && /^machine:/ { sub(/^machine:[[:space:]]*/, ""); gsub(/["\047]/, ""); s = $0 }
                END { printf "{\"project\":\"%s\",\"cron\":\"%s\",\"schedule\":\"%s\",\"machine\":\"%s\"}\n", p, n, c, s }' "$m" >> "${tmp}/cron"
        done
    done

    # The containers running here, whichever engine the stack uses (podman first,
    # as adhoc picks). The controller's Grafana pages when one that was is gone.
    : > "${tmp}/container"
    for e in podman docker; do
        command -v "$e" >/dev/null 2>&1 || continue
        { "$e" ps --format '{{.Names}} {{.Image}}' 2>/dev/null || true; } \
            | awk 'NF { printf "{\"name\":\"%s\",\"image\":\"%s\"}\n", $1, $2 }' > "${tmp}/container"
        break
    done

    # Every run, live: alloy tails the same projects' runs/ into the same Loki
    # (lib/reporting/decree.alloy), in its own tmux session. Its read positions
    # are in the store, so a run that ends while it is down is sent once it is
    # back. A new Loki address restarts it.
    host="$(hostname -s 2>/dev/null || hostname)"
    # shellcheck source=/dev/null
    . "${repo}/services/automation/decree/tmx.sh"
    if command -v alloy >/dev/null 2>&1; then
        if [[ "$(cat "${store}/alloy-loki" 2>/dev/null || true)" != "$loki" ]]; then
            tmux kill-session -t "=reporting-alloy" 2>/dev/null || true
            printf '%s\n' "$loki" > "${store}/alloy-loki"
        fi
        mkdir -p "${store}/alloy"
        tmx -d reporting-alloy "EXIST_REPO='${repo}' EXIST_HOST='${host}' EXIST_LOKI='${loki%/}/loki/api/v1/push' exec alloy run '${DECREE_LIB}/reporting/decree.alloy' --storage.path='$(cd "${store}/alloy" && pwd)' --server.http.listen-addr=127.0.0.1:12346 --disable-reporting"
        runs="runs shipped live by alloy (tmux attach -t reporting-alloy)"
    else
        runs="no runs shipped: alloy is not on PATH"
    fi

    # The controller, with ntfy on: what another host's notify pushed to Loki
    # ({job="exist", kind="notify"}), published to this ntfy, in tmux as
    # notify-relay (lib/reporting/relay.sh). It reads the Loki address from the
    # store each time, so a new one needs no restart.
    if [[ -z "$ctl" ]] && grep -q '^EXIST_IS_SERVICES_NTFY=true' "${repo}/.env.shared" 2>/dev/null; then
        tmx -d notify-relay "exec bash '${DECREE_LIB}/reporting/relay.sh' '$(cd "$store" && pwd)' '${repo}'"
    fi

    # One Loki push: a stream per kind, each line a JSON string. The timestamp is
    # now plus a nanosecond per line, so no two lines of a stream share one.
    now="$(date +%s)"
    {
        printf '{"streams":['
        sep=""
        for kind in disk load machine plugin cron container; do
            [[ -s "${tmp}/${kind}" ]] || continue
            printf '%s{"stream":{"job":"exist","host":"%s","kind":"%s"},"values":[' "$sep" "$host" "$kind"
            sed 's/\\/\\\\/g; s/"/\\"/g' "${tmp}/${kind}" \
                | awk -v s="$now" '{ printf "%s[\"%s%09d\",\"%s\"]", (NR > 1 ? "," : ""), s, NR, $0 }'
            printf ']}'
            sep=","
        done
        printf ']}'
    } > "${tmp}/body"

    curl -fsS --max-time 20 -H 'Content-Type: application/json' \
        --data-binary @"${tmp}/body" "${loki%/}/loki/api/v1/push" >/dev/null
    echo "reporting: ${host} to ${loki}: $(wc -l < "${tmp}/disk" | tr -d ' ') disks, $(cat "${tmp}/load"), $(wc -l < "${tmp}/machine" | tr -d ' ') machines, $(wc -l < "${tmp}/plugin" | tr -d ' ') plugins, $(wc -l < "${tmp}/cron" | tr -d ' ') crons, $(wc -l < "${tmp}/container" | tr -d ' ') containers, ${runs}"
lib:
  reporting/relay.sh: |
    #!/usr/bin/env bash
    # notify-relay <store> <repo> — on the controller: every message another host's
    # notify pushed to Loki ({job="exist", kind="notify"}, a JSON line of topic,
    # title, priority, tags and body), published to this host's ntfy as the shared
    # publisher. report starts it in tmux (notify-relay). Its place is
    # <store>/relay-cursor, so a message sent while it is down is published once it
    # is back; one ntfy refuses is tried again, in order. Needs jq.
    #
    # On the host, so bash 3.2 and BSD tools on a Mac: no date +%N.
    set -uo pipefail
    store="$1" repo="$2"
    ntfy=http://127.0.0.1:44680   # where services/ntfy publishes itself on the host
    command -v jq >/dev/null 2>&1 || { echo "notify-relay: needs jq on this host"; exit 1; }
    env_get() { sed -n "s/^$1=//p" "${repo}/.env.shared" 2>/dev/null | head -1; }
    cursor="${store}/relay-cursor"
    [[ -s "$cursor" ]] || echo "$(date +%s)000000000" > "$cursor"
    while :; do
        loki="$(cat "${store}/loki" 2>/dev/null || true)"
        if [[ -n "$loki" ]] && out="$(curl -fsSG --max-time 10 "${loki%/}/loki/api/v1/query_range" \
                --data-urlencode 'query={job="exist", kind="notify"}' --data-urlencode "start=$(( $(cat "$cursor") + 1 ))" \
                --data-urlencode direction=forward --data-urlencode limit=200)"; then
            printf '%s' "$out" | jq -c '[.data.result[] | .stream.host as $h | .values[]
                    | {ts: .[0], host: $h, m: ((.[1] | fromjson?) // {})}] | sort_by(.ts) | .[]' |
            while IFS= read -r e; do
                if [[ -z "$(jq -r '.m.body // ""' <<<"$e")" ]]; then jq -r .ts <<<"$e" > "$cursor"; continue; fi
                set -- -fsS --max-time 20 -u "$(env_get EXIST_NTFY_USER):$(env_get EXIST_NTFY_PASSWORD)"
                for h in Title:title Priority:priority Tags:tags; do
                    v="$(jq -r --arg k "${h#*:}" '.m[$k] // ""' <<<"$e" | tr -d '\r\n')"
                    [[ -z "$v" ]] || set -- "$@" -H "${h%%:*}: $v"
                done
                topic="$(jq -r '.m.topic // "" | if . == "" then "decree" else . end' <<<"$e")"
                if jq -r '.m.body // ""' <<<"$e" | curl "$@" --data-binary @- "${ntfy}/${topic}" >/dev/null; then
                    jq -r .ts <<<"$e" > "$cursor"
                    echo "notify-relay: $(jq -r .host <<<"$e") → ${topic}"
                else
                    echo "notify-relay: ntfy refused a message from $(jq -r .host <<<"$e"); trying again"; break
                fi
            done
        fi
        sleep 15
    done
  reporting/decree.alloy: |
    // Every decree run on this host, live, into the Loki its controller names.
    // report starts it (tmux session reporting-alloy) with EXIST_REPO, EXIST_HOST
    // and EXIST_LOKI set. decree 0.5 writes each run's record as
    // runs/<id>/events.jsonl and each script's output as
    // runs/<id>/<NNNN>-<state>-<script>.log; the event log is the telemetry.
    // The projects are existential's own, the ones report lists machines for.
    //
    // These labels are a contract: grafana's decree dashboards and the decree
    // alerts query them. Low cardinality only: run_id is metadata, never a label.

    loki.source.file "decree_events" {
    	targets = [
    		{ __path__ = sys.env("EXIST_REPO") + "/volumes/workspace_data/.decree/runs/*/events.jsonl", job = "decree", host = sys.env("EXIST_HOST"), project = "automation" },
    		{ __path__ = sys.env("EXIST_REPO") + "/services/automation-backup/runs/*/events.jsonl", job = "decree", host = sys.env("EXIST_HOST"), project = "automation-backup" },
    		{ __path__ = sys.env("EXIST_REPO") + "/host/.decree/runs/*/events.jsonl", job = "decree", host = sys.env("EXIST_HOST"), project = "host" },
    	]
    	forward_to = [loki.process.decree_events.receiver]
    	file_match {
    		enabled = true
    	}
    }

    loki.process "decree_events" {
    	forward_to = [loki.write.default.receiver]
    	stage.json {
    		expressions = { ts = "", type = "", machine = "", run_id = "" }
    	}
    	// decree's own timestamp, not the time alloy read the line.
    	stage.timestamp {
    		source = "ts"
    		format = "RFC3339"
    	}
    	stage.labels {
    		values = { type = "", machine = "" }
    	}
    	stage.structured_metadata {
    		values = { run_id = "" }
    	}
    	// filename names the run: a label per run is what run_id avoids.
    	stage.label_drop {
    		values = ["filename"]
    	}
    }

    // Each script's stdout+stderr, as <NNNN>-<state>-<script>.log, or
    // <NNNN>-<state>.log when the script is the state's own. Neither name can
    // contain "-", so the path regex is unambiguous.
    loki.source.file "decree_script_output" {
    	targets = [
    		{ __path__ = sys.env("EXIST_REPO") + "/volumes/workspace_data/.decree/runs/*/[0-9]*.log", job = "decree_script", host = sys.env("EXIST_HOST"), project = "automation" },
    		{ __path__ = sys.env("EXIST_REPO") + "/services/automation-backup/runs/*/[0-9]*.log", job = "decree_script", host = sys.env("EXIST_HOST"), project = "automation-backup" },
    		{ __path__ = sys.env("EXIST_REPO") + "/host/.decree/runs/*/[0-9]*.log", job = "decree_script", host = sys.env("EXIST_HOST"), project = "host" },
    	]
    	forward_to = [loki.process.decree_script_output.receiver]
    	file_match {
    		enabled = true
    	}
    }

    loki.process "decree_script_output" {
    	forward_to = [loki.write.default.receiver]
    	stage.regex {
    		source     = "filename"
    		expression = "/(?P<run_id>[^/]+)/(?P<n>\\d{4,})-(?P<state>[^-/.]+)(?:-(?P<script>[^/]+))?\\.log$"
    	}
    	stage.labels {
    		values = { script = "" }
    	}
    	stage.structured_metadata {
    		values = { run_id = "", state = "" }
    	}
    	stage.label_drop {
    		values = ["filename"]
    	}
    }

    loki.write "default" {
    	endpoint {
    		url = sys.env("EXIST_LOKI")
    	}
    }
cron:
  reporting: |
    ---
    machine: reporting
    cron: "*/5 * * * *"
    ---
---
# reporting

Every 5 minutes, this host's free space on `/` and each disk under `/mnt`, its average CPU %, RAM and GPU VRAM used and total, the decree machines, plugins and crons installed in each of its
projects, the containers running, and every run that finished since the last report, sent to the Loki its controller
names. Grafana's **Hosts** dashboard shows every host that reports. The `worker` flow
turns it on. With `EXIST_CONTROLLER` set, it asks that controller; blank, this host is the
controller, and names the Loki in `EXIST_REPORTING_URL`, or its own. See
/docs/hosting/controller-and-workers.
