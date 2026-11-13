---
machine: plugin
automation: reporting
chart:
  description: Report this host to the Loki its controller names - free disk space, CPU, RAM and VRAM use, the decree machines installed, and every run since the last report.
  store:
    loki: The Loki push address the controller last gave, used while it cannot be reached. report reads and writes it.
    shipped: Stamp of the last report that landed; a run newer than it has not been sent. report reads and touches it.
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
    # (CPU, RAM, VRAM) once, kind=machine per installed decree machine, kind=run
    # per run finished since the last push. Grafana's Hosts dashboard reads them.
    # job="exist" keeps them apart from alloy's job="decree", so no run is
    # counted twice.
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
    touch "${tmp}/now"   # runs finishing while this one reads are in the next report

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

    : > "${tmp}/machine"; : > "${tmp}/run"
    for p in automation:volumes/workspace_data/.decree automation-backup:services/automation-backup host:host/.decree; do
        name="${p%%:*}" dir="${repo}/${p#*:}"
        [[ -d "$dir" ]] || continue
        for m in "$dir"/machines/*.yml; do
            [[ -f "$m" ]] || continue
            printf '{"project":"%s","machine":"%s"}\n' "$name" "$(basename "$m" .yml)" >> "${tmp}/machine"
        done
        [[ -d "${dir}/runs" ]] || continue
        if [[ -f "${store}/shipped" ]]; then newer=(-newer "${store}/shipped"); else newer=(); fi
        find "${dir}/runs" -name events.jsonl ${newer[@]+"${newer[@]}"} 2>/dev/null | while IFS= read -r ev; do
            { grep -hE '"type"[[:space:]]*:[[:space:]]*"run_finished"' "$ev" || true; } | tail -1 | sed "s/^{/{\"project\":\"${name}\",/"
        done >> "${tmp}/run"
    done

    # One Loki push: a stream per kind, each line a JSON string. The timestamp is
    # now plus a nanosecond per line, so no two lines of a stream share one.
    host="$(hostname -s 2>/dev/null || hostname)"
    now="$(date +%s)"
    {
        printf '{"streams":['
        sep=""
        for kind in disk load machine run; do
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
    cp -p "${tmp}/now" "${store}/shipped"
    echo "reporting: ${host} to ${loki}: $(wc -l < "${tmp}/disk" | tr -d ' ') disks, $(cat "${tmp}/load"), $(wc -l < "${tmp}/machine" | tr -d ' ') machines, $(wc -l < "${tmp}/run" | tr -d ' ') runs"
cron:
  reporting: |
    ---
    machine: reporting
    cron: "*/5 * * * *"
    ---
---
# reporting

Every 5 minutes, this host's free space on `/` and each disk under `/mnt`, its average CPU %, RAM and GPU VRAM used and total, the decree machines installed in each of its
projects, and every run that finished since the last report, sent to the Loki its controller
names. Grafana's **Hosts** dashboard shows every host that reports. The `worker` flow
turns it on. With `EXIST_CONTROLLER` set, it asks that controller; blank, this host is the
controller, and names the Loki in `EXIST_REPORTING_URL`, or its own. See
/docs/hosting/controller-and-workers.
