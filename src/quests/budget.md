---
name: Budget Automation
tagline: Bank alert emails become Actual Budget transactions
e2e: false
e2e_skip: Requires a Gmail OAuth grant and real bank alert mail
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
done:
  files:
    - volumes/workspace_data/.decree/cron/gmail-sync.md
---

A cron polls a Gmail label every 15 minutes, parses bank alert emails with a
bank-specific parser, and posts transactions to Actual Budget.

Docs: https://existential.company/docs/decree/transaction-gmail-actual-budget

── 0. First run of Actual Budget ─────────────────────────────────────────

Actual Budget needs a budget file before anything can post to it. Open
https://actual-budget.${EXIST_DOMAIN} and create one, or bootstrap it
non-interactively:

       ./existential.sh run actual-budget setup

Its whole database lives in one volume — one cron file backs it up, see the
**Backups** quest.

── 1. Prerequisites ──────────────────────────────────────────────────────

  - Gmail connected — the **Gmail Integration** quest

── 2. Label the mail ─────────────────────────────────────────────────────

In Gmail, create a label for your bank's alert emails and a filter that applies
it automatically. Then record the label id:

       ./existential.sh run automation gmail-labels

That writes GMAIL_LABEL_ID into `automation/secrets/gmail/`.

── 3. Teach it your bank ─────────────────────────────────────────────────

Every bank words its alerts differently, so the parser is yours to write. Copy
the Chase one and adapt it:

       automation/lib/actual-budget/parse-chase.ts

Then point a Gmail label at it and an Actual Budget account:

       ./existential.sh run automation gmail-transactions-cron

── 4. Activate the poller ────────────────────────────────────────────────

       mkdir -p volumes/workspace_data/.decree/cron/

       # Pulls new mail every 15 minutes
       cp automation-examples/cron/gmail-sync.md volumes/workspace_data/.decree/cron/

── 5. Watch the first one land ───────────────────────────────────────────

Run logs are in `volumes/workspace_data/.decree/runs/`, and in Grafana's Decree Overview dashboard
filtered by `routine=actual-budget-parse`. A parse that finds nothing is a
parser problem, not a plumbing problem — the mail is in the run log either way.
