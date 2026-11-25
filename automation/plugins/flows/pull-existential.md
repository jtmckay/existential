---
name: pull-existential
x-exist-title: Pull existential
x-exist-tagline: Every 15 minutes, git pull, ./existential.sh and docker compose up -d, so this install follows its branch
x-exist-docs: /docs/hosting/updates
x-exist-project: host
needs:
  - pull_existential
---
It runs in a decree daemon on the host (the repo's own .decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says. A pull that cannot fast-forward
changes nothing, and your phone says why.
