---
sidebar_position: 9
---

# Prometheus

- Source: https://github.com/prometheus/prometheus
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- UI: `https://prometheus.<domain>`

Time-series metrics database. Collects numeric measurements and stores them for querying and alerting.

## What's configured

This stack runs Prometheus alongside a **Pushgateway**, which is how Decree automations push metrics rather than being scraped directly.

| Service | Port | Role |
|---|---|---|
| `prometheus` | 9090 (internal) | Stores and queries metrics |
| `prometheus-pushgateway` | 9091 (internal) | Receives pushed metrics from short-lived jobs |

Prometheus scrapes Pushgateway every 15s and retains data for 90 days or 5 GB, whichever comes first.

## How metrics get in

The `afterEach` hook in `automations/lib/hooks/afterEach.sh` fires after every Decree run and pushes three gauges to Pushgateway:

| Metric | Labels |
|---|---|
| `decree_run_success` | `trigger_type`, `instance=<routine>` |
| `decree_run_duration_seconds` | same |
| `decree_run_attempts` | same |

Decree's **triage** routine pushes one more, and it is the one to graph if you want a single
answer to "is anything broken":

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

## Viewing metrics

Raw metric explorer at `https://prometheus.<domain>`. For dashboards, use [Grafana](./grafana).
