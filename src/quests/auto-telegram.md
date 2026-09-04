---
name: Telegram Bot
tagline: Connect a Telegram bot to Decree for notifications and image ingestion
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

Create a Telegram bot and wire it to Decree. Once connected, Decree can
send you transaction notifications and receive photos for OCR processing.
Docs: https://existential.company/docs/integrations/telegram

Setup:
  1. Message @BotFather on Telegram to create a bot. Copy the token.

  2. Write the token to automation/secrets/telegram/credentials.env:
         TELEGRAM_BOT_TOKEN=<your-token>

  3. Get your chat ID: send a message to your bot, then run:
         printf -- '---\nroutine: telegram-ingest\n---\n' > automation/inbox/telegram-ingest.md

  4. Add TELEGRAM_CHAT_ID to the credentials file.

  5. Activate the poller — checks for new photo messages every 30 minutes
     and routes them to MinIO for downstream processing:
       mkdir -p automation/cron/
       cp automation-examples/cron/telegram-poll.md automation/cron/
       docker compose restart automation
