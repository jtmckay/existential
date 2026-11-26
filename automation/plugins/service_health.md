---
name: service_health
x-exist-topic: host
x-exist-project: automation
machine:
  description: Probe one service's HTTP endpoint and fail unless it answers with the expected status.
  data:
    SERVICE_NAME: {type: string, default: ""}
    SERVICE_URL: {type: string, default: ""}
    EXPECT_CODE: {type: int, default: 200}
    # Seconds.
    TIMEOUT: {type: int, default: 5}
  initial: probe
  states:
    probe:
      invoke: service_health
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  service_health.sh: |
    #!/usr/bin/env bash
    # service_health — HTTP probe for a single service endpoint.
    #
    # Runs in the main decree daemon (on the exist Docker network) on a cron
    # schedule. Every run lands in Loki ({job="decree", machine="service_health"}),
    # so a failing probe is a failed run, which the daemon reports like any other.
    #
    # SERVICE_NAME, SERVICE_URL, EXPECT_CODE and TIMEOUT are the machine's data
    # (SERVICE_URL blank probes where notifications go):
    #
    #   ---
    #   cron: "*/15 * * * *"
    #   machine: service_health
    #   params:
    #     SERVICE_NAME: mealie
    #     SERVICE_URL: http://mealie:9000/api/app/about
    #   ---
    set -euo pipefail

    SERVICE_NAME="${DECREE_DATA_SERVICE_NAME:-notifications}"
    SERVICE_URL="$DECREE_DATA_SERVICE_URL"
    EXPECT_CODE="$DECREE_DATA_EXPECT_CODE"
    TIMEOUT="$DECREE_DATA_TIMEOUT"

    # Blank: where this host's notifications go. Its own ntfy, or, with ntfy off
    # here, the controller's Loki (NTFY_URL is then Loki's push address).
    if [[ -z "$SERVICE_URL" ]]; then
        case "${NTFY_URL:-http://ntfy:80}" in
            */loki/api/v1/push) SERVICE_URL="${NTFY_URL%/loki/api/v1/push}/ready" ;;
            *)                  SERVICE_URL="${NTFY_URL:-http://ntfy:80}/v1/health" ;;
        esac
    fi

    # A container name (no dot) that the generated compose (/work/docker-compose.yml,
    # every service that is on) does not run is a service that is off here: skipped,
    # not failed. An address with a dot, another host's, is always probed.
    target="${SERVICE_URL#*://}"; target="${target%%[:/]*}"
    compose=/work/docker-compose.yml
    if [[ "$target" != *.* && -f "$compose" ]] &&
        ! grep -qE "^[[:space:]]+container_name:[[:space:]]*[\"']?${target}[\"']?[[:space:]]*$" "$compose"; then
        printf '[%s] %s is not on here; skipped\n' "$SERVICE_NAME" "$target"
        exit 0
    fi

    printf '[%s] probe %s\n' "$SERVICE_NAME" "$SERVICE_URL"

    http_code=$(curl -fsS -o /dev/null -w "%{http_code}" \
        --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
        "$SERVICE_URL" 2>/dev/null || echo "000")

    if [[ "$http_code" == "$EXPECT_CODE" ]]; then
        printf '[%s] HTTP %s  OK\n' "$SERVICE_NAME" "$http_code"
    elif [[ "$http_code" == "000" ]]; then
        printf '[%s] no response within %ss  FAIL\n' "$SERVICE_NAME" "$TIMEOUT" >&2
        exit 1
    else
        printf '[%s] HTTP %s (expected %s)  FAIL\n' "$SERVICE_NAME" "$http_code" "$EXPECT_CODE" >&2
        exit 1
    fi
cron:
  health-checks.md: |
    ---
    cron: "*/15 * * * *"
    machine: service_health
    params:
      SERVICE_NAME: notifications
    ---

    Health check cron template for all services accessible from the main decree
    daemon on the exist Docker network.

    Each check is a separate cron file. Copy this file and adjust SERVICE_NAME and
    SERVICE_URL for each service you want to monitor.

    The shipped default leaves SERVICE_URL blank: it checks where this host's
    notifications go, its ntfy, or the controller's Loki when ntfy is off here. A
    check on a container this host does not run (a service that is off here) is
    skipped, not failed, so a copy can stay in place on every host. Results appear
    in Grafana's Decree Overview, from Loki.

    The run's machine is "service_health", not SERVICE_NAME — every copy of
    this cron shares one. The per-service
    alert in hosting/prometheus/alerts.yml rides triage's exist_service_healthy
    gauge instead, which needs no cron file at all.

    Example service URLs (container:port/health-path):
      http://ollama:11434/api/tags            - ollama
      http://mealie:9000/api/app/about        - mealie
      http://nocodb:8080/api/v1/health        - nocodb (unauthenticated)
      http://grafana:3000/api/health          - grafana
      http://prometheus:9090/-/healthy        - prometheus
      http://loki:3100/ready                  - loki
      http://automation-webhook:8801/healthz  - automation-webhook
      http://uptime-kuma:3001               - uptime-kuma (any 200)
      http://open-webui:8080/health           - open-webui
---
# service_health

Probe one service's HTTP endpoint and fail unless it answers with the expected status.
