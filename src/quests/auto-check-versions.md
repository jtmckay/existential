---
name: Weekly Version Updates
tagline: Get notified when image updates are available for your services
e2e: false
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
---

Adds a weekly cron to Decree that queries upstream registries and sends
an ntfy notification listing any services with newer image tags available.
Silent when everything is current.

Activate it:
  mkdir -p services/decree/decree/cron/
  cp services/decree/decree/cron.example/check-versions.md services/decree/decree/cron/
  docker compose restart decree

How it works:
  - Every Monday at 09:00 Decree runs check-versions
  - It reads current tags from the generated docker-compose.yml
  - It queries Docker Hub and GitHub for latest releases
  - If any tags are behind, it fires an ntfy notification

When you get an update notification:
  ./existential.sh run check-versions --update   # patches .exist.yml files
  docker compose pull                            # pull new images
  docker compose up -d                           # restart updated services

After applying updates, re-run ./existential.sh to regenerate
docker-compose.yml so the next weekly check sees the new pinned tags.
