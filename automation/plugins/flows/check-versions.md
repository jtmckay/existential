---
name: check-versions
x-exist-title: Version updates
x-exist-tagline: Fridays at noon, a notification listing every pinned image with a newer version upstream
x-exist-docs: /docs/hosting/updates#pinned-images
x-exist-project: host
needs:
  - check_versions
cron:
  check-versions.md: |
    ---
    cron: "0 12 * * FRI"
    machine: check_versions
    ---

    Fridays at 12:00, every pinned image against upstream. One ntfy notification
    lists each that is behind; silent when all are current.
---
It runs in a decree daemon on the host (the repo's own .decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

When one arrives:
  ./existential.sh run check-versions --update
  ./existential.sh && docker compose up -d
