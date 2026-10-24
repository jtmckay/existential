---
name: Apps
tagline: Actual Budget, Mealie and IT Tools — everyday apps, and the first things decree can feed
e2e: true
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget (personal finance)
  - var: EXIST_IS_SERVICES_MEALIE
    label: Mealie (recipes)
  - var: EXIST_IS_SERVICES_IT_TOOLS
    label: IT Tools (developer utilities)
---

An add-on, not part of Core. Actual Budget is envelope budgeting on your own
disk, and the app decree can already post to: bank alert emails become
transactions (the **Budget Automation** quest). Mealie keeps recipes from a URL
and builds the shopping list from a meal plan. IT Tools is a static page of
developer utilities (base64, JWT, hashes, cron, UUIDs) that runs entirely in
your browser.

── 1. Enable and start ───────────────────────────────────────────────────

Turn on the ones you want:

       EXIST_IS_SERVICES_ACTUAL_BUDGET=true
       EXIST_IS_SERVICES_MEALIE=true
       EXIST_IS_SERVICES_IT_TOOLS=true

       ./existential.sh
       docker compose up -d

Each is reached at https://<slug>.${EXIST_DOMAIN}, so this needs the
**Network** quest's Caddy.

── 2. Actual Budget: set the password and make a budget ──────────────────

Open https://actual-budget.${EXIST_DOMAIN}. The server has no default
password: the first screen sets it. Then create a budget file.

Want decree to reach it? `./existential.sh run actual-budget setup` saves the
credentials routines use.

── 3. Mealie: change the default login ───────────────────────────────────

Signup is off, so there is one account, created on first boot:
changeme@example.com / MyPassword. Log in at https://mealie.${EXIST_DOMAIN} and
change both under Settings > User Profile.

── 4. IT Tools ───────────────────────────────────────────────────────────

Open https://it-tools.${EXIST_DOMAIN}. No account, no data, nothing to
configure or back up.

       ./existential.sh test actual-budget mealie it-tools

── What to build on this ─────────────────────────────────────────────────

**Budget Automation**. Backups (Mealie's Postgres and uploads, Actual Budget's
data) are cron files: the **Backups** quest. Other apps (Immich, NocoDB, ...)
are one flag each in the service picker.
