---
name: Core
tagline: Open the work dir, talk to an AI, have decree automate it
e2e: true
services:
  - var: EXIST_IS_HOSTING_CADDY
    label: Caddy (TLS + hostnames)
  - var: EXIST_IS_SERVICES_DASHY
    label: Dashy (the dashboard — links to everything below)
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (editor + terminal over the workspace)
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (automation engine + its webhook)
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy (push notifications — where automations report in)
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki (log store — Decree's run logs land here)
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus (metrics store)
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana (the window onto both — ships Decree dashboards)
  - var: EXIST_IS_HOSTING_UPTIME_KUMA
    label: Uptime Kuma (is the rest of the homelab up?)
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget (personal finance)
copies:
  - src: automation-examples/cron/clean-runs.md
    dst: volumes/workspace_data/.decree/cron/
    label: "decree: clean-runs.md (prune old run logs weekly)"
    requires: EXIST_IS_SERVICES_AUTOMATION
  - src: automation-examples/cron/health-checks.md
    dst: volumes/workspace_data/.decree/cron/
    label: "decree: health-checks.md"
    requires: EXIST_IS_SERVICES_AUTOMATION
---

Core is three things: open the work dir, talk to an AI about it, and have
decree automate what you would otherwise do by hand. Everything below runs on
one ordinary box. No GPU, no model downloads.

What you get:
  code-server            the work dir in a browser tab: editor, plus a terminal
                         where you run the AI CLI you use
  Decree                 runs routines on a schedule, a webhook or an inbox
                         message, headless
  ntfy                   how a finished automation tells you it finished
  Loki + Grafana         every Decree run log, searchable, with two dashboards
                         wired up before you get there
  Prometheus             the metrics behind those dashboards
  Uptime Kuma            whether the rest of your homelab is up
  Actual Budget          budgeting, and the first app decree can post to
  Caddy                  https://<service>.<domain> for every one of them
  Dashy                  one page linking to all of the above

Files (Nextcloud), the house (Home Assistant), DNS (piHole) and GPU models
usually run on other servers, so Core leaves them out. Each is one unnumbered
quest away: **Nextcloud**, **Voice & Home**, **Local AI**.

Core is the fast path, not the only one. Quests 01–05 are these same ten
services cut into five pieces you can do one at a time, by hand. Run Core and
01–04 cross themselves off (Apps ends in a password only its own UI knows);
run them individually and you arrive at the same stack.

── Sizing ──────────────────────────────────────────────────────────────────

About 15 containers, no GPU and nothing to download beyond the images. Every
one carries a memory limit, so a runaway query cannot take the box down with
it. `./existential.sh run footprint core` adds them up.

code-server idles around 200 MB with nobody connected; its 2 GB limit is
headroom for an actual editing session (language servers, a terminal, the CLI
you install in it). Its first boot downloads the editor and four extensions
before it answers, a couple of minutes on a fresh install.

── After `docker compose up -d` ────────────────────────────────────────────

  Check everything: ./existential.sh test services

Open https://dashy.<domain>: your landing page, with a link and a live status
dot for every core service. ./existential.sh prints the URL when it finishes.

1. Open https://code-server.<domain> (password: CODE_SERVER_PASSWORD in
   services/code-server/.env), open a terminal, and install the AI CLI you use
   (`npm i -g <package>`). It survives container recreation. That terminal,
   over the work dir, is where you talk to the AI.

2. Subscribe to ntfy. Its entrypoint already created your admin login
   (services/ntfy/.env) and the exist-bot publisher Decree uses. Point the ntfy
   mobile app at https://ntfy.<domain>, log in as the admin, and subscribe to
   the "decree" topic.

3. Grafana comes up with Loki and Prometheus wired and two Decree dashboards
   loaded. When a routine misbehaves, look there: every run log is labelled
   with its message_id, chain and seq. Credentials: hosting/grafana/.env.

Two apps make you create the first account in their own UI:

4. Uptime Kuma: open https://uptime-kuma.<domain>, create the admin, add
   monitors for your other machines, and point notifications at ntfy
   (server http://ntfy:80).

5. Actual Budget: open https://actual-budget.<domain>, set the password,
   create a budget file.

Then automate something: the **Automation** quest shows the one mechanism
(copy a template into volumes/workspace_data/.decree/cron/), and every unnumbered quest is a
variation on it.
