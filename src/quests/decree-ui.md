---
name: Decree Routine UI
tagline: Trigger decree machines from a Lowcoder control panel in the browser
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_SERVICES_LOWCODER
    label: Lowcoder
---

Decree is headless by design, but a Lowcoder app can serve as a control
panel — one button or form per webhook endpoint. automation-webhook describes
every endpoint it serves at /openapi.json, so Lowcoder builds the queries
itself; there is nothing to generate.

Prerequisites:
  - Decree running (Quest 03 — Automation)
  - Lowcoder enabled (EXIST_IS_SERVICES_LOWCODER=true — no quest, it comes
    up configured)

Setup:
  1. The endpoints are automation/decree-go-rest.yml. Add one per machine you
     want a button for; edits are live without a restart.

  2. In Lowcoder (https://lowcoder.${EXIST_DOMAIN}), add a data source of
     type OpenAPI:
         Spec URL:  http://automation-webhook:8801/openapi.json
         Auth:      Bearer token, AUTOMATION_WEBHOOK_SECRET from
                    services/automation/.env

  3. Build the app: each endpoint is now a query. A path parameter becomes a
     query input to bind to a text field; the request body is plain text.
     A 201 means the message is queued; `docker exec automation decree status`
     shows the run.
