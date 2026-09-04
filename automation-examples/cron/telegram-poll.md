---
cron: "*/30 * * * *"
routine: telegram-ingest
TELEGRAM_RCLONE_DEST: nextcloud:S3/telegram
---

Poll Telegram bot every minute for new photo messages and save them to MinIO for OCR processing.
Copy to telegram-poll.md and set TELEGRAM_BOT_TOKEN in /secrets/telegram/credentials.env to activate.
