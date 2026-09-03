---
name: Smart Home
tagline: Automate your home, get notified, and wire up routines
e2e: true
services:
  - var: EXIST_IS_SERVICES_HOMEASSISTANT
    label: Home Assistant
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy
---

Home Assistant runs the house; Decree is what reacts on a schedule; ntfy is
how a finished automation tells you about it.

None of the crons below are required to use Home Assistant on its own — only
copy the ones for automations you actually want. All of them live in the same
decree project, so one restart picks up everything you copied:

  mkdir -p services/decree/decree/cron/

  # Prune old run logs weekly — worth having no matter what else you enable
  cp services/decree/decree/cron.example/clean-runs.md services/decree/decree/cron/

  # Gmail sync — only if you're wiring up email-driven automations
  # (full setup: the auto-gmail quest)
  cp services/decree/decree/cron.example/gmail-sync.md services/decree/decree/cron/

  # Telegram bot polling — only if you connected a bot
  # (full setup: the auto-telegram quest)
  cp services/decree/decree/cron.example/telegram-poll.md services/decree/decree/cron/

  # Telegram receipt-photo polling — only if you're using receipt-split
  # (full setup: the auto-receipt-split quest)
  cp services/decree/decree/cron.example/telegram-receipt-poll.md services/decree/decree/cron/

  docker compose restart decree

The Gmail and Telegram crons on their own do nothing useful yet — they poll
for messages, but nothing is wired to act on what they find until you set up
the OAuth/bot credentials each one needs. Run the auto-gmail, auto-telegram
and auto-receipt-split quests for the rest of that setup; copy the cron here
first so it's ready by the time you finish it.
