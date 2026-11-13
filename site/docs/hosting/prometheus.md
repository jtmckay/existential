---
service: hosting/prometheus
sidebar_position: 9
---

# Prometheus

- Source: https://github.com/prometheus/prometheus
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- UI: `https://prometheus.<domain>`

Time-series metrics database. Collects numeric measurements and stores them for querying and alerting.

## What's configured

This stack runs Prometheus alongside a **Pushgateway** (where triage pushes its per-service
health gauge) and **node-exporter** (host CPU/memory/disk metrics).

| Service | Port | Role |
|---|---|---|
| `prometheus` | 9090 (internal) | Stores and queries metrics |
| `prometheus-pushgateway` | 9091 (internal) | Receives pushed metrics from short-lived jobs |
| `prometheus-node-exporter` | 9100 (internal) | Exposes host CPU/memory/disk/filesystem metrics |

Prometheus scrapes itself, Pushgateway and node-exporter every 15s and retains data for
90 days or 5 GB, whichever comes first.

## How metrics get in

Decree runs are not metrics here: each run's `events.jsonl` is its record, in [Loki](./loki.md),
where Grafana counts and times them. Decree's **triage** machine pushes one metric to
Pushgateway, and it is the one to graph if you want a single answer to "is anything broken":

| Metric | Labels |
|---|---|
| `exist_service_healthy` | `service`, `category` |

It is `1` when that service's own `exist.test.sh` passes and `0` when it does not — the same
check `./existential.sh test services` runs, on a schedule. Triage is on by default and quiets
itself as the stack stays green, backing its interval off while everything passes and tightening
up again when something breaks. It notifies on **change** only, so a healthy stack is silent and
a newly broken service is not.

Prometheus pulls these into its time series on the next scrape interval.

## Adding more scrapers

Edit `hosting/prometheus/prometheus.yml` and add a new entry under `scrape_configs`. Any container on the `exist` network is reachable by container name.

## Alert rules

`hosting/prometheus/alerts.yml` defines host-resource alerts (disk/memory/CPU, off node-exporter),
and a service-health alert (`ServiceHealthCheckFailing`, off triage's `exist_service_healthy` gauge —
see above).

**There is no Alertmanager in this stack.** These rules are visible at
`https://prometheus.<domain>/alerts` and nowhere else. The alerts that reach you are
[Grafana](./grafana.md)'s, off Loki: a run in `automation-backup` or a host's own project that ends
in `failed`, and a backup machine with no run ended `done` in 48 hours, each send an ntfy
notification.
The `automation` daemon reports its own failed and waiting runs without either
([When a run needs you](../decree/decree.md#when-a-run-needs-you)).

## Viewing metrics

Raw metric explorer at `https://prometheus.<domain>`. For dashboards, use [Grafana](./grafana.md).
