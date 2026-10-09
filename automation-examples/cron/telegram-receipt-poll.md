---
cron: "*/30 * * * *"
machine: telegram_receipt
params:
  TELEGRAM_RCLONE_DEST: nextcloud:telegram
---

Poll Telegram bot every minute for receipt photos and split-revert replies.
Copy to telegram-receipt-poll.md and configure /secrets/telegram/credentials.env to activate.
