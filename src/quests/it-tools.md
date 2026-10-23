---
name: IT Tools
tagline: The drawer of developer utilities — base64, JWT, hashes, cron, UUIDs — on your own box
e2e: false
services:
  - var: EXIST_IS_SERVICES_IT_TOOLS
    label: IT Tools (developer utilities)
---

A static page of developer utilities. Everything runs in your browser: no
account, no data, nothing to configure or back up.

── Enable and start ──────────────────────────────────────────────────────

       EXIST_IS_SERVICES_IT_TOOLS=true

       ./existential.sh
       docker compose up -d

Open https://it-tools.${EXIST_DOMAIN}.

       ./existential.sh test it-tools
