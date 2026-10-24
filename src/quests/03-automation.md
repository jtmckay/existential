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
    - volumes/workspace_data/.decree/cron/clean-runs.md
    - volumes/workspace_data/.decree/cron/health-checks.md
---

The engine slice of Core. Decree runs routines on a schedule or on a message
you drop in its inbox; ntfy is where a finished routine tells you
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

       mkdir -p volumes/workspace_data/.decree/cron/

       # Prunes old run logs weekly, so volumes/workspace_data/.decree/runs/ cannot grow forever
       cp automation-examples/cron/clean-runs.md volumes/workspace_data/.decree/cron/

       # Probes ntfy every 15 minutes (see the Service Health quest)
       cp automation-examples/cron/health-checks.md volumes/workspace_data/.decree/cron/

That is it. Every unnumbered quest in this picker is a variation on those three
lines — a different template, occasionally a different daemon.

── 3. The two daemons ────────────────────────────────────────────────────

There is no per-service sidecar. There are exactly two containers:

  automation         everything that reasons, routes, or calls a service API,
                     plus every service's one-time migrations.
                     crons: automation-examples/cron/ → volumes/workspace_data/.decree/cron/

  automation-backup  mounts volumes/ wholesale and holds every service's
                     credentials, and does no reasoning. Backups live here, and
                     so do notes_pull and triage.
                     crons: services/automation/backup/cron.example/
                            → services/automation/backup/cron/

Pick the daemon by what the work needs to reach, not by what it is called.

── 4. Drive it ───────────────────────────────────────────────────────────

Decree is headless — there is no click-through UI. Run a machine by hand:

       echo | docker exec -i automation decree emit --machine clean_runs
       docker exec automation decree status

The same works from code-server's terminal, over the work dir:

       cd /workspace && echo | decree emit --machine clean_runs

Want it over HTTP? The **Capture** quest adds automation-webhook. Want
buttons? The **Decree Routine UI** quest generates a Lowcoder panel. Want it on
your phone? ntfy, below.

── 5. Subscribe to ntfy ──────────────────────────────────────────────────

ntfy set itself up on first boot — there is no token to mint. Install the app
or open https://<machine>.<tailnet>.ts.net:8443 (the **Access** slice), sign in with the admin credentials in
`services/ntfy/.env`, and subscribe to the `decree` topic. Full detail, and the
bot account routines publish as: the **Notifications (ntfy)** quest.

       ./existential.sh test ntfy

── Where the runs go ─────────────────────────────────────────────────────

Every run writes a log to `volumes/workspace_data/.decree/runs/`. Turn on the **Monitoring**
quest and those become searchable in Grafana with a dashboard already built.
