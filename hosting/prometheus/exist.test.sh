#!/usr/bin/env bash
# exist.test.sh — validate that prometheus + pushgateway are operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "prometheus" EXIST_IS_HOSTING_PROMETHEUS
skip_if_disabled

probe_service "prometheus /-/healthy" prometheus 9090 /-/healthy 200
probe_service "prometheus /-/ready"   prometheus 9090 /-/ready   200

# pushgateway is not fronted by caddy — direct only.
http_probe "prometheus-pushgateway /-/healthy" \
           "http://prometheus-pushgateway:9091/-/healthy" 200

finish
