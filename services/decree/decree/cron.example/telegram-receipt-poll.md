---
cron: "*/30 * * * *"
routine: telegram-receipt
TELEGRAM_RCLONE_DEST: nextcloud:S3/telegram
---

Poll Telegram bot every minute for receipt photos and split-revert replies.
Copy to telegram-receipt-poll.md and configure /secrets/telegram/credentials.env to activate.
