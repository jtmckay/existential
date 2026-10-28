---
service: hosting/loki
sidebar_position: 10
---

# Loki

- Source: https://github.com/grafana/loki
- License: [AGPL 3.0](https://www.gnu.org/licenses/agpl-3.0.html)

Log aggregation system. Indexes log metadata (labels) rather than full text, keeping storage cheap while still supporting rich log queries in Grafana.

## What's configured

Two containers work together:

| Service | Role |
|---|---|
| `loki` | Stores and indexes logs (port 3100 internal) |
| `loki-alloy` | Tails log files and ships them to Loki |

[Grafana Alloy](https://github.com/grafana/alloy) replaced Promtail, which Grafana declared feature-complete and end-of-lifed in March 2026. Its config (`loki-alloy-config.alloy`) is written in Alloy's own configuration language, not YAML.

Alloy is mounted read-only on both decree projects' `runs/` and tails each run's
`events.jsonl` (decree's own record, one JSON line per step) as `{job="decree"}` and each
script's output as `{job="decree_script"}`:

| Label | Values |
|---|---|
| `daemon` | `automation`, `automation-backup` |
| `machine` | the machine that ran (`events.jsonl` lines) |
| `type` | `transition`, `script`, `run_finished`, … (`events.jsonl` lines) |
| `script` | the script that wrote the output (`decree_script` lines) |

`run_id` is structured metadata, not a label, so one run is `{job="decree"} | run_id="<id>"`.
The same pipeline turns every `run_finished` line into Prometheus metrics; see
[Prometheus](./prometheus).

It also tails every container's `json-file` log under `/var/lib/docker/containers` as `{job="docker"}`. Those lines have no container name, only the container id in `filename` (`docker inspect` it): naming them would need the Docker socket, which is host root.

It tails [Hermes](../ai/hermes)' own log files too, as `{job="hermes"}`, off a read-only mount of
the `logs` subpath of its volume. That mount is the only way hermes reaches Loki at all: it logs
to files under `$HERMES_HOME/logs` and never to stdout, so `docker logs hermes-agent` is empty and
the `{job="docker"}` catch-all above cannot see it. What lands there is the part of hermes you
otherwise cannot observe — the cron scheduler's per-profile tick lines, a `tool <name> completed`
record for every tool call the agent makes, and the tracebacks behind any failure:

| Label | Values |
|---|---|
| `level` | `INFO`, `WARNING`, `ERROR` — parsed off each record |
| `log_type` | `auth` on the dashboard's login log only; absent on the rest |
| `event` | `login_success`, `refresh_failure`, … (`log_type="auth"` lines) |

Two deliberate omissions. `errors.log` is not tailed — every line in it also appears in
`agent.log`, so tailing both shows each error twice. And the module name (`cron.scheduler_provider`,
`agent.tool_executor`) is not a label: it's unbounded, so it stays in the line where a
`|=` filter handles it.

:::note[Hermes' scheduler is not decree's]
A cron job created by hermes — `hermes cron create`, `/cron` in its chat, or the agent deciding to
schedule one mid-task — lives in *its* volume, not in `volumes/workspace_data/.decree/cron/`. `decree status --cron` cannot see
it and the Decree dashboards do not count it. This log job is what makes those firings visible at
all: query `{job="hermes"} |= "cron"`.
:::

## Storage

Single-node filesystem storage under `/loki` in the volume `loki_data`, TSDB index on schema v13. Old samples beyond 168h (7 days) are rejected on ingest, and the compactor deletes anything older than 720h (30 days). The embedded query cache is capped at 100 MB.

## Querying

Loki is not meant to be queried directly. Use [Grafana](./grafana) with the pre-configured Loki datasource and LogQL:

```logql
{job="decree", type="run_finished"} | json | state != "done"
{job="decree", machine="gmail_sync", type="run_finished"} | json | duration_ms > 10000
{job="hermes", level="ERROR"}
{job="hermes"} |= "tool " |= "completed"
{job="hermes", log_type="auth"} | json | event != "ws_ticket_minted"
```
