---
sidebar_position: 1
---

# Integrations

Integrations are optional services that connect Existential to external platforms. Each one requires an interactive setup step — they can't be configured automatically during the initial `./existential.sh` run.

All integration setup scripts run inside the `existential-adhoc` container, so nothing needs to be installed on your host machine.

```bash
./existential.sh run <slug> <action>    # e.g. run automation gmail-sync
./existential.sh run <name>             # general utilities, e.g. run rclone
```

Exact commands differ per integration — see each page below.

| Integration | What it does |
|---|---|
| [Actual Budget](./actual-budget) | Post transactions to Actual Budget from bank alert emails |
| [Gmail](./gmail) | Read-only Gmail access for the `gmail-sync` automation |
| [rclone](./rclone) | Remote file storage — Nextcloud, Dropbox, S3, and more |
| [Telegram](./telegram) | Transaction notifications and receipt-photo split flow |
