---
name: Budget Automation
tagline: Bank alert emails become Actual Budget transactions, and a receipt photo splits one into line items
e2e: false
e2e_skip: Requires a Gmail OAuth grant, a Telegram bot, and real bank alert mail
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
done:
  files:
    - automation/cron/gmail-sync.md
---

Two halves of the same loop. A cron polls a Gmail label every 15 minutes,
parses bank alert emails with a bank-specific parser, and posts transactions to
Actual Budget. Then — optionally — Decree pings you on Telegram, you reply with
a photo of the receipt, and it splits that transaction into line items without
you leaving the chat.

Docs: https://existential.company/docs/decree/transaction-gmail-actual-budget
      https://existential.company/docs/decree/receipt-split

── 0. First run of Actual Budget ─────────────────────────────────────────

Actual Budget needs a budget file before anything can post to it. Open
https://actual-budget.${EXIST_DOMAIN} and create one, or bootstrap it
non-interactively:

       ./existential.sh run actual-budget setup

Its whole database lives in one volume — one cron file backs it up, see the
**Backups** quest.

── 1. Prerequisites ──────────────────────────────────────────────────────

  - Gmail connected — the **Gmail Integration** quest
  - Telegram bot connected, for the receipt half — the **Telegram Bot** quest

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

── 4. Activate the pollers ───────────────────────────────────────────────

       mkdir -p automation/cron/

       # Pulls new mail every 15 minutes
       cp automation-examples/cron/gmail-sync.md automation/cron/

       # Receipt half — checks for photo replies every 30 minutes, matches them
       # to outstanding transactions and triggers the split
       cp automation-examples/cron/telegram-receipt-poll.md automation/cron/

── 5. Watch the first one land ───────────────────────────────────────────

Run logs are in `automation/runs/`, and in Grafana's Decree Overview dashboard
filtered by `routine=actual-budget-parse`. A parse that finds nothing is a
parser problem, not a plumbing problem — the mail is in the run log either way.
