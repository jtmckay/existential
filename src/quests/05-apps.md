---
name: Apps
tagline: Actual Budget — the one everyday app Core ships, and the first thing decree can feed
e2e: true
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget (personal finance)
---

The apps slice of Core. Actual Budget is envelope budgeting on your own disk,
and the app decree can already post to: bank alert emails become transactions
(the **Budget Automation** quest).

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_ACTUAL_BUDGET=true

       ./existential.sh
       docker compose up -d

── 2. Set the password and make a budget ─────────────────────────────────

Open https://actual-budget.${EXIST_DOMAIN}. The server has no default
password: the first screen sets it. Then create a budget file.

Want decree to reach it? `./existential.sh run actual-budget setup` saves the
credentials routines use.

       ./existential.sh test actual-budget

── What to build on this ─────────────────────────────────────────────────

**Budget Automation**. Other apps (Mealie, IT Tools, Immich, NocoDB, ...) are
one flag each in the service picker; Mealie and IT Tools have their own quests.
