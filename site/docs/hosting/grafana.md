---
sidebar_position: 11
---

# Grafana

- Source: https://github.com/grafana/grafana
- License: [AGPL 3.0](https://www.gnu.org/licenses/agpl-3.0.html)
- UI: `http://localhost:43010`
- Credentials: `EXIST_DEFAULT_USERNAME` / `EXIST_DEFAULT_PASSWORD` (set via `.env.exist`)

Visualization layer for [Prometheus](./prometheus) metrics and [Loki](./loki) logs. Everything is provisioned from code — no manual setup needed.

![Grafana](./img/grafana.png)

## What's provisioned

| Resource | File | Purpose |
|---|---|---|
| Prometheus datasource | `provisioning/datasources/prometheus.yaml` | Default datasource, 15s scrape interval |
| Loki datasource | `provisioning/datasources/loki.yaml` | Log queries, max 1000 lines |
| Decree Overview dashboard | `provisioning/dashboards/decree-overview.json` | Pre-built Decree monitoring |

Grafana re-reads the provisioning directory every 30 seconds, so changes to files take effect without a restart.

## Decree Overview dashboard

Covers the Decree automation engine with panels for:

- **Current Status** — last run success/failure per routine (Prometheus gauges)
- **Run logs** — live log stream from Loki, filterable by routine, trigger type, and exit code

This is the main place to check when a Decree automation fails or behaves unexpectedly.

## Extending

- **New dashboard**: drop a JSON export into `hosting/grafana/provisioning/dashboards/`. Grafana auto-loads it.
- **New datasource**: add a YAML file to `hosting/grafana/provisioning/datasources/`.
- **Alerts**: configure in the Grafana UI or add alert rules to dashboard JSON — they persist in the `grafana_data` volume.

## Data flow summary

```
Decree run
  └─ afterEach.sh
       ├─ Pushgateway → Prometheus (metrics: success, duration, attempts)
       └─ Loki push API (log: structured summary line)

automations/runs/**/routine.log
  └─ Promtail → Loki (full routine output, labeled by run_id/chain/seq)

Grafana
  ├─ queries Prometheus for metric panels
  └─ queries Loki for log panels
```
