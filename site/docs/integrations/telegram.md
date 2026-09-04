---
sidebar_position: 4
---

# Telegram

Connects Decree to a Telegram bot for sending transaction notifications and receiving receipt photos. Once configured, Decree automatically notifies you of new transactions and lets you split them by replying with a photo of the receipt.

## Creating a Bot

### 1. Create the bot with @BotFather

Open Telegram and message [@BotFather](https://t.me/BotFather):

```
/newbot
```

Follow the prompts — choose a name and username. BotFather will reply with your **bot token**:

```
123456789:ABCDEFGHijklmnopQRSTuvwxyz1234567890
```

Keep this token secret. Anyone with it can send messages as your bot.

### 2. Get your chat ID

Start a conversation with your bot (search for it by username and click **Start**). Then message [@userinfobot](https://t.me/userinfobot) — it will reply with your numeric chat ID:

```
Id: 987654321
```

This is the `TELEGRAM_CHAT_ID` — it tells Decree which chat to send notifications to.

:::tip[Group chats]
You can also add the bot to a group and use the group's chat ID (negative number, e.g. `-1001234567890`). Get a group's ID by forwarding a message from it to @userinfobot.
:::

### 3. Save credentials

```bash
mkdir -p automation/secrets/telegram
cat > automation/secrets/telegram/credentials.env << 'EOF'
TELEGRAM_BOT_TOKEN=your-bot-token-here
TELEGRAM_CHAT_ID=your-chat-id-here
EOF
```

The secrets directory is bind-mounted into the decree container at `/secrets/telegram/`.

## Enabling Routines

`telegram-notify` and `telegram-receipt` are already enabled by default in
`services/automation/decree/config.yml` — there's nothing to flip there. What
actually gates them is the credentials file above (`telegram-notify` is chained
from `actual-budget`'s outbox and does nothing without it) and, for receipt
polling, activating its cron:

```bash
cp automation-examples/cron/telegram-receipt-poll.md \
   automation/cron/
```

Cron frontmatter is read when the daemon starts, so restart it to pick the new schedule up:

```bash
docker compose restart automation
```

## Verifying

Check the routines pass pre-checks:

```bash
docker exec automation decree routine telegram-notify
docker exec automation decree routine telegram-receipt
```

Send a test message from your bot to confirm the chat ID is correct:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID>&text=test"
```

## State File

Decree stores pending transaction and split state in `/secrets/telegram/state.json`. This file is read and written by `telegram-notify` and `telegram-receipt`. You can inspect it at any time:

```bash
cat automation/secrets/telegram/state.json | jq .
```

To clear all pending state (e.g. after testing):

```bash
echo '{"pending":{},"splits":{},"last_pending_message_id":null}' \
  > automation/secrets/telegram/state.json
```
