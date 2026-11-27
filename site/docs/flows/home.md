---
sidebar_position: 7
---

# Money, Photos and the House

The rest of life, on the same hardware and in the same files.

## Bank alerts become budget entries

Each charge alert your bank emails becomes an [Actual Budget](../services/actual-budget.md)
transaction, payee and amount filled in, a few minutes after you pay.

```bash
./existential.sh service on actual-budget
./existential.sh plugin on gmail_sync
docker compose up -d
```

What only you can do, once:

1. **At your bank**, turn on an email alert for every transaction, not just large ones, sent to
   your Gmail. Not every bank offers it.
2. **In Gmail**, filter those alerts into a label of their own, one label per bank
   (*Filter messages like these → Apply the label*).
3. **Connect the pieces**, in order:

   ```bash
   ./existential.sh run automation gmail-sync              # read-only Gmail access, in a browser
   ./existential.sh run actual-budget setup                # your budget and its accounts
   ./existential.sh run automation gmail-transactions-cron # this label goes to that account
   ```

   The last one offers the schedule in `workspace/ai/proposed/`; move it as it says to turn it
   on.

Chase alerts are read out of the box. Another bank needs its own small parser:
[Actual Budget](../integrations/actual-budget.md#another-bank).

## Your photos

[Immich](../services/immich.md): your photos and videos, backed up from your phone and
searchable, with your NAS photos added read-only.

```bash
./existential.sh service on immich
./existential.sh plugin on immich_setup
docker compose up -d
```

The admin account is made for you, with your `EXIST_EMAIL` and `EXIST_PASSWORD`. Sign in at
`https://immich.<domain>`; the phone app takes the same login.

## Talk to the house

Ask out loud and the house answers, through your own [Home Assistant](../services/homeassistant.md):
speech in and out on your hardware, your chat model answering. No cloud assistant.

```bash
./existential.sh service on homeassistant wyoming-whisper wyoming-piper
./existential.sh plugin on homeassistant_voice
docker compose up -d
```

The admin account and the voice pipeline are made once Home Assistant answers. Then, at
`https://homeassistant.<domain>`: *Settings → Voice assistants*, and add your devices from Home
Assistant's own screens.

## Office documents

Word, Excel and PowerPoint files, edited in the browser, in your Nextcloud.

```bash
./existential.sh service on nextcloud collabora
./existential.sh plugin on nextcloud_richdocuments
docker compose up -d
```

More: [Collabora](../storage/collabora.md).
