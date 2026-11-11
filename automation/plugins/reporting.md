---
machine: plugin
automation: reporting
chart:
  description: Report this host to the Loki its controller names - free disk space, the decree machines installed, and every run since the last report.
  store:
    loki: The Loki push address the controller last gave, used while it cannot be reached. report reads and writes it.
    shipped: Stamp of the last report that landed; a run newer than it has not been sent. report reads and touches it.
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
    # One push, labelled {job="exist", host, kind}: kind=disk per real filesystem,
    # kind=machine per installed decree machine, kind=run per run finished since
    # the last push. Grafana's Hosts dashboard reads them. job="exist" keeps
    # them apart from alloy's job="decree", so no run is counted twice.
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

    # A real filesystem is a device; tmpfs, overlay and loop mounts are not disks.
    df -Pk | awk 'NR > 1 && $1 ~ "^/dev/" && $1 !~ "^/dev/loop" {
        m = $6; for (i = 7; i <= NF; i++) m = m " " $i
        printf "{\"mount\":\"%s\",\"device\":\"%s\",\"size_kb\":%s,\"avail_kb\":%s}\n", m, $1, $2, $4 }' > "${tmp}/disk"

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
        for kind in disk machine run; do
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
    echo "reporting: ${host} to ${loki}: $(wc -l < "${tmp}/disk" | tr -d ' ') disks, $(wc -l < "${tmp}/machine" | tr -d ' ') machines, $(wc -l < "${tmp}/run" | tr -d ' ') runs"
cron:
  reporting: |
    ---
    machine: reporting
    cron: "*/5 * * * *"
    ---
---
# reporting

Every 5 minutes, this host's free disk space, the decree machines installed in each of its
projects, and every run that finished since the last report, sent to the Loki its controller
names. Grafana's **Hosts** dashboard shows every host that reports. The `worker` flow
turns it on. With `EXIST_CONTROLLER` set, it asks that controller; blank, this host is the
controller, and names the Loki in `EXIST_REPORTING_URL`, or its own. See
/docs/hosting/controller-and-workers.
