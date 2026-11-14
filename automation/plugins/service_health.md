---
machine: plugin
automation: service_health
chart:
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
  service_health: |
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
---
# service_health

Probe one service's HTTP endpoint and fail unless it answers with the expected status.
