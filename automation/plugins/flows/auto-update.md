---
machine: plugin
automation: auto-update
name: Auto-update
tagline: Every 15 minutes, git pull, ./existential.sh and docker compose up -d, so this install follows its branch
docs: /docs/hosting/updates
project: host
needs:
  - update
---
It runs in a decree daemon on the host (host/.decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/updates says. A pull that cannot fast-forward
changes nothing, and your phone says why.
