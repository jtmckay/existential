---
name: Gmail Integration
tagline: Connect Decree to your Gmail inbox for email-driven automations
e2e: false
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
---

Grants Decree read-only Gmail access via OAuth 2.0. Required by the
bank transaction import and receipt split automations.
Docs: https://existential.company/docs/integrations/gmail

Setup:
  1. ./existential.sh run decree gmail-sync
     Opens a browser OAuth flow and writes credentials to
     automations/secrets/gmail/.

  2. Activate the poller — checks for new messages every 15 minutes:
       mkdir -p services/decree/decree/cron/
       cp services/decree/decree/cron.example/gmail-sync.md services/decree/decree/cron/
       docker compose restart decree
