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
| `promtail` | Tails log files and ships them to Loki |

Promtail is mounted read-only on `automations/runs/` and watches `**/routine.log`. It parses the path to extract labels from the run ID format (`D<date>-<time>-<routine>-<seq>`):

| Label | Example |
|---|---|
| `run_id` | `D20250502-1430-gmail-sync-1` |
| `chain` | `D20250502-1430-gmail-sync` |
| `seq` | `1` |

In addition, the `afterEach` hook pushes a structured summary line to Loki after each Decree run — one event per attempt with `routine`, `trigger`, `exit_code`, `attempts`, `duration_s`, and `final` fields.

## Storage

Single-node filesystem storage under `/loki` in the named volume `loki_data`. Old samples beyond 168h (7 days) are rejected on ingest. The embedded query cache is capped at 100 MB.

## Querying

Loki is not meant to be queried directly. Use [Grafana](./grafana) with the pre-configured Loki datasource and LogQL:

```logql
{job="decree"} |= "exit_code=0"
{job="decree", routine="gmail-sync"} | logfmt | duration_s > 10
```
