---
name: Receipt Split
tagline: Reply to a transaction notification with a receipt photo to split it automatically
e2e: false
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

When a bank alert lands, Decree notifies you via Telegram. Reply with
a photo of your receipt and Decree automatically splits the transaction
into line items in Actual Budget — without leaving Telegram.
Docs: https://existential.company/docs/decree/receipt-split

Prerequisites:
  - Bank Transaction Import set up (auto-budget-import quest)
  - Telegram Bot connected (auto-telegram quest)

Activate the poller — checks for receipt-photo replies every 30 minutes,
matches them to outstanding transactions, and triggers the split via the
actual-budget routine:
  mkdir -p automation/cron/
  cp automation-examples/cron/telegram-receipt-poll.md automation/cron/
  docker compose restart automation
