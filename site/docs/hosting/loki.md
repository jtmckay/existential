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
| `loki` | Stores and indexes logs. Port 3100 on the exist network, on `127.0.0.1:43100`, and on the tailnet at `http://<host>:3100`, where every machine's reporting plugin pushes ([Controller and Workers](./controller-and-workers.md)) |
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
[Prometheus](./prometheus.md).

It also tails every container's `json-file` log under `/var/lib/docker/containers` as `{job="docker"}`. Those lines have no container name, only the container id in `filename` (`docker inspect` it): naming them would need the Docker socket, which is host root.

## Storage

Single-node filesystem storage under `/loki` in the volume `loki_data`, TSDB index on schema v13. Old samples beyond 168h (7 days) are rejected on ingest, and the compactor deletes anything older than 720h (30 days). The embedded query cache is capped at 100 MB.

## Querying

Loki is not meant to be queried directly. Use [Grafana](./grafana.md) with the pre-configured Loki datasource and LogQL:

```logql
{job="decree", type="run_finished"} | json | state != "done"
{job="decree", machine="gmail_sync", type="run_finished"} | json | duration_ms > 10000
```
