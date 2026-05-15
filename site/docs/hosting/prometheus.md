---
sidebar_position: 9
---

# Prometheus

- Source: https://github.com/prometheus/prometheus
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- UI: `http://localhost:49090`

Time-series metrics database. Collects numeric measurements and stores them for querying and alerting.

## What's configured

This stack runs Prometheus alongside a **Pushgateway**, which is how Decree automations push metrics rather than being scraped directly.

| Service | Port | Role |
|---|---|---|
| `prometheus` | 49090 | Stores and queries metrics |
| `pushgateway` | 9091 (internal) | Receives pushed metrics from short-lived jobs |

Prometheus scrapes Pushgateway every 15s and retains data for 90 days.

## How metrics get in

The `afterEach` hook in `automations/hooks/afterEach.sh` fires after every Decree run and pushes three gauges to Pushgateway:

| Metric | Labels |
|---|---|
| `decree_run_success` | `trigger_type`, `instance=<routine>` |
| `decree_run_duration_seconds` | same |
| `decree_run_attempts` | same |

Prometheus pulls these into its time series on the next scrape interval.

## Adding more scrapers

Edit `hosting/prometheus/prometheus.yml` and add a new entry under `scrape_configs`. Any container on the `exist` network is reachable by container name.

## Viewing metrics

Raw metric explorer at `http://localhost:49090`. For dashboards, use [Grafana](./grafana).
