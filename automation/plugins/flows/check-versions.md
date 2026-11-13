---
machine: plugin
automation: check-versions
name: Version updates
tagline: Fridays at noon, a notification listing every pinned image with a newer version upstream
docs: /docs/hosting/updates#pinned-images
project: host
needs:
  - check_versions
cron:
  check-versions: |
    ---
    cron: "0 12 * * FRI"
    machine: check_versions
    ---

    Fridays at 12:00, every pinned image against upstream. One ntfy notification
    lists each that is behind; silent when all are current.
---
It runs in a decree daemon on the host (host/.decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

When one arrives:
  ./existential.sh run check-versions --update
  ./existential.sh && docker compose up -d
