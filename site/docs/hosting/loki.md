---
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

Alloy is mounted read-only on `automations/runs/` and watches `**/routine.log` and `**/message.md`. It parses the path to extract labels from the run ID format (`D<day>-<time>-<routine>-<seq>`):

| Label | Example |
|---|---|
| `message_id` | `D0005-0750-gmail-sync-0` |
| `chain` | `D0005-0750-gmail-sync` |
| `seq` | `0` |

It also tails every container's `json-file` log under `/var/lib/docker/containers` as `{job="docker"}`. Those lines carry no container-name label, only the 64-hex container id in `filename` — resolving that to a name would mean either the Docker socket (deliberately not mounted — that's full API access, i.e. host root) or parsing the undocumented internal `config.v2.json` next to each log file, which was rejected as a worse trade than an id you can `docker inspect` by hand. So it's a catch-all grep, not a per-service view.

In addition, the `afterEach` hook pushes a structured summary line to Loki after each Decree run — one event per attempt with `routine`, `trigger`, `exit_code`, `attempts`, `duration_s`, and `final` fields.

## Storage

Single-node filesystem storage under `/loki` in the volume `loki_data`, TSDB index on schema v13. Old samples beyond 168h (7 days) are rejected on ingest, and the compactor deletes anything older than 720h (30 days). The embedded query cache is capped at 100 MB.

## Querying

Loki is not meant to be queried directly. Use [Grafana](./grafana) with the pre-configured Loki datasource and LogQL:

```logql
{job="decree"} |= "exit_code=0"
{job="decree", routine="gmail-sync"} | logfmt | duration_s > 10
```
