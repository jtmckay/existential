#!/usr/bin/env bash
# exist.test.sh — validate prometheus, pushgateway and node-exporter.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "prometheus" EXIST_IS_HOSTING_PROMETHEUS
skip_if_disabled

probe_service "prometheus /-/healthy" prometheus 9090 /-/healthy 200
probe_service "prometheus /-/ready"   prometheus 9090 /-/ready   200

# pushgateway and node-exporter are not fronted by caddy — direct only.
http_probe "prometheus-pushgateway /-/healthy" \
           "http://prometheus-pushgateway:9091/-/healthy" 200

# node-exporter serves no /-/healthy endpoint; /metrics is the liveness signal.
http_probe "prometheus-node-exporter /metrics" \
           "http://prometheus-node-exporter:9100/metrics" 200

finish
