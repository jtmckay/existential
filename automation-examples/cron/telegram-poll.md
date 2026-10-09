---
cron: "*/30 * * * *"
machine: telegram_ingest
params:
  TELEGRAM_RCLONE_DEST: nextcloud:telegram
---

Poll Telegram bot every minute for new photo messages and save them to the bucket for OCR processing.
Copy to telegram-poll.md and set TELEGRAM_BOT_TOKEN in /secrets/telegram/credentials.env to activate.
