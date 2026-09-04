---
name: Smart Home
tagline: Automate your home, get notified, and wire up routines
e2e: true
services:
  - var: EXIST_IS_SERVICES_HOMEASSISTANT
    label: Home Assistant
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy
---

Home Assistant runs the house; Decree is what reacts on a schedule; ntfy is
how a finished automation tells you about it.

None of the crons below are required to use Home Assistant on its own — only
copy the ones for automations you actually want. All of them live in the same
decree project, so one restart picks up everything you copied:

  mkdir -p automation/cron/

  # Prune old run logs weekly — worth having no matter what else you enable
  cp automation-examples/cron/clean-runs.md automation/cron/

  # Gmail sync — only if you're wiring up email-driven automations
  # (full setup: the auto-gmail quest)
  cp automation-examples/cron/gmail-sync.md automation/cron/

  # Telegram bot polling — only if you connected a bot
  # (full setup: the auto-telegram quest)
  cp automation-examples/cron/telegram-poll.md automation/cron/

  # Telegram receipt-photo polling — only if you're using receipt-split
  # (full setup: the auto-receipt-split quest)
  cp automation-examples/cron/telegram-receipt-poll.md automation/cron/

  docker compose restart automation

The Gmail and Telegram crons on their own do nothing useful yet — they poll
for messages, but nothing is wired to act on what they find until you set up
the OAuth/bot credentials each one needs. Run the auto-gmail, auto-telegram
and auto-receipt-split quests for the rest of that setup; copy the cron here
first so it's ready by the time you finish it.
