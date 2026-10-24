---
name: Core
tagline: Open the work dir, talk to an AI, have decree automate it
e2e: true
services:
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (editor + terminal over the workspace)
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (the automation daemon)
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy (push notifications — where automations report in)
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
decree automate what you would otherwise do by hand. That is the whole loop:
write in code-server, ask Claude there, decree runs it, ntfy tells you.

What you get:
  code-server            the work dir in a browser tab: editor, plus a terminal
                         with claude and opencode ready
  Decree                 runs routines on a schedule or an inbox message,
                         headless
  ntfy                   how a finished automation tells you it finished
  Tailscale (host)       real HTTPS to both, on every device you log in, with
                         no reverse proxy and no certificate to install

Everything else is an add-on, one unnumbered quest each: **Network** (Caddy
hostnames, LAN access without Tailscale), **Monitoring**, **Capture** (the
webhook and Nextcloud), **Apps**, **Local AI**, **Voice & Home**. Most installs
run files, DNS, the house and GPU models on other servers anyway.

Core is the fast path, not the only one. Quests 01–03 are these same pieces
one at a time, by hand. Run Core and 02–03 cross themselves off; run them
individually and you arrive at the same stack.

── Before you start: Tailscale ─────────────────────────────────────────────

Install Tailscale on this host and log in (https://tailscale.com/download),
then do the same on every phone and laptop that should reach Core. Quest
**01 Access** has the details.

── Sizing ──────────────────────────────────────────────────────────────────

A handful of containers, no GPU and no model pulls: nothing to download beyond
the images. Every one carries a memory limit, so a runaway process cannot take
the box down with it. `./existential.sh run footprint core` adds them up.

code-server idles around 200 MB with nobody connected; its 2 GB limit is
headroom for an actual editing session (language servers, a terminal, the CLI
you install in it). Its first boot downloads the editor and four extensions
before it answers, a couple of minutes on a fresh install.

── After `docker compose up -d` ────────────────────────────────────────────

  Check everything: ./existential.sh test services

1. Open code-server at https://<machine>.<tailnet>.ts.net (password:
   CODE_SERVER_PASSWORD in services/code-server/.env) and open a terminal:
   `claude` and `opencode` are already there, and their logins survive
   container recreation. That terminal, over the work dir, is where you talk
   to the AI.

2. Subscribe to ntfy. Its entrypoint already created your admin login
   (services/ntfy/.env) and the exist-bot publisher Decree uses. Point the ntfy
   mobile app at https://<machine>.<tailnet>.ts.net:8443, log in as the admin,
   and subscribe to the "decree" topic.

3. Keep the workspace safe: put it under git, with a remote you choose. It is
   the simplest backup there is, and Core ships no other.
     cd volumes/workspace_data && git init && git add -A && git commit -m start
     git remote add origin <your remote> && git push -u origin HEAD

Then automate something: the **Automation** quest shows the one mechanism
(copy a template into volumes/workspace_data/.decree/cron/), and every
unnumbered quest is a variation on it.
