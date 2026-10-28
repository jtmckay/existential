---
sidebar_position: 1
---

# Integrations

Connections to outside services. Each needs one interactive setup step, run inside the
`existential-adhoc` container, so nothing is installed on the host.

```bash
./existential.sh run <slug> <action>    # e.g. run automation gmail-sync
./existential.sh run <name>             # general utilities, e.g. run rclone
```

Exact commands differ per integration — see each page below.

| Integration | What it does |
|---|---|
| [Actual Budget](./actual-budget) | Post transactions to Actual Budget from bank alert emails |
| [Gmail](./gmail) | Read-only Gmail access for the `gmail_sync` automation |
| [rclone](./rclone) | Remote file storage — Nextcloud, Dropbox, S3, and more |
