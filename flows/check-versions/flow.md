---
name: Version updates
tagline: Mondays, a notification listing every service with a newer image
docs: /docs/flows#housekeeping
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
---

When one arrives:
  ./existential.sh run check-versions --update
  ./existential.sh && docker compose pull && docker compose up -d
