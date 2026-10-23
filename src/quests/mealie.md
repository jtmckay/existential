---
name: Mealie
tagline: Recipes from a URL, meal plans, and a shopping list that adds itself up
e2e: false
services:
  - var: EXIST_IS_SERVICES_MEALIE
    label: Mealie (recipes)
---

Paste a recipe URL and Mealie keeps the ingredients and steps; plan the week
and it builds the shopping list.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_MEALIE=true

       ./existential.sh
       docker compose up -d

── 2. Change the default login ───────────────────────────────────────────

Signup is off, so there is one account, created on first boot:
changeme@example.com / MyPassword. Log in at https://mealie.${EXIST_DOMAIN} and
change both under Settings > User Profile.

       ./existential.sh test mealie

Backups (Postgres plus the uploads volume) are two cron files: the **Backups**
quest. Docs: https://existential.company/docs/services/mealie
