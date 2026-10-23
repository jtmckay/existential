---
name: Workspace
tagline: code-server — an editor and a terminal over the work dir, from any browser
e2e: true
services:
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (editor + terminal over the workspace)
done:
  files:
    - services/code-server/.env
---

The work dir slice of Core. The workspace (`volumes/workspace_data`) is the one
tree that is yours: you edit it in code-server, an AI agent works in it from
code-server's terminal, and decree's routines read and write it.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_CODE_SERVER=true

       ./existential.sh
       docker compose up -d

First boot downloads the editor and four extensions before it answers, so give
it a couple of minutes. The password is CODE_SERVER_PASSWORD in
services/code-server/.env.

── 2. Talk to an AI there ────────────────────────────────────────────────

Open https://code-server.${EXIST_DOMAIN}, open a terminal, and install the AI
coding CLI you use (`npm i -g <package>`). The install and its login survive a
container recreation, because the home directory lives on a volume. From then
on that terminal is where you start a conversation about the work dir.

       ./existential.sh test code-server

── What to build on this ─────────────────────────────────────────────────

Have decree run the repeatable parts (the **Automation** slice). To sync the
workspace to your other machines, add the **Nextcloud** quest. For a local
model and agent, add the **Local AI** quest.
