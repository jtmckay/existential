---
name: Automation
tagline: Decree runs the scheduled and event-driven work; ntfy is how it reports back
e2e: true
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (automation engine)
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy (push notifications)
done:
  files:
    - automation/cron/clean-runs.md
    - automation/cron/health-checks.md
---

The engine slice of Core. Decree runs routines on a schedule, on a webhook, or
on a message you drop in its inbox; ntfy is where a finished routine tells you
about it. Everything past this quest is "a cron file and a routine".

Docs: https://existential.company/docs/decree

Core activates the two crons below for you. Doing it by hand is the whole point
of this quest — every other automation in this stack is the same two commands.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_AUTOMATION=true
       EXIST_IS_SERVICES_NTFY=true

       ./existential.sh
       docker compose up -d

── 2. Learn the one mechanism ────────────────────────────────────────────

A cron is a markdown file with frontmatter. Tracked templates ship *next to*
the live directory; copying one in is what activates it. Restart the daemon
that owns it and it is live:

       mkdir -p automation/cron/

       # Prunes old run logs weekly, so automation/runs/ cannot grow forever
       cp automation-examples/cron/clean-runs.md automation/cron/

       # Probes a service URL every 15 minutes (see the Service Health quest)
       cp automation-examples/cron/health-checks.md automation/cron/

       docker compose restart automation

That is it. Every unnumbered quest in this picker is a variation on those three
lines — a different template, occasionally a different daemon.

── 3. The two daemons ────────────────────────────────────────────────────

There is no per-service sidecar. There are exactly two containers:

  automation         everything that reasons, routes, or calls a service API,
                     plus every service's one-time migrations.
                     crons: automation-examples/cron/ → automation/cron/

  automation-backup  mounts volumes/ wholesale and holds every service's
                     credentials, and does no reasoning. Backups live here, and
                     so do notes-pull and triage.
                     crons: services/automation/backup/cron.example/
                            → services/automation/backup/cron/

Pick the daemon by what the work needs to reach, not by what it is called.

── 4. Drive it ───────────────────────────────────────────────────────────

Decree is headless — there is no click-through UI. Trigger a routine by hand:

       printf -- '---\nroutine: clean-runs\n---\n' > automation/inbox/manual.md

Or over HTTP at https://automation-webhook.${EXIST_DOMAIN} (an API, not a UI).
Want buttons? The **Decree Routine UI** quest generates a Lowcoder panel. Want
it on your phone? The **Telegram Bot** quest.

── 5. Subscribe to ntfy ──────────────────────────────────────────────────

ntfy set itself up on first boot — there is no token to mint. Install the app
or open https://ntfy.${EXIST_DOMAIN}, sign in with the admin credentials in
`services/ntfy/.env`, and subscribe to the `decree` topic. Full detail, and the
bot account routines publish as: the **Notifications (ntfy)** quest.

       ./existential.sh test ntfy

── Where the runs go ─────────────────────────────────────────────────────

Every run writes a log to `automation/runs/`. Turn on the **Observability**
quest and those become searchable in Grafana with a dashboard already built.
