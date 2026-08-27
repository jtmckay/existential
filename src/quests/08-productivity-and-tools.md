---
name: Productivity & Tools
tagline: Tasks, databases, and low-code apps
e2e: true
services:
  - var: EXIST_IS_SERVICES_NOCODB
    label: NocoDB
  - var: EXIST_IS_SERVICES_APPSMITH
    label: Appsmith
  - var: EXIST_IS_SERVICES_LOWCODER
    label: Lowcoder
  - var: EXIST_IS_SERVICES_IT_TOOLS
    label: IT Tools
copies:
  - src: services/nocodb/decree/cron.example/nocodb-db-backup-nightly.md
    dst: services/nocodb/decree/cron/
    label: "nocodb: db-backup-nightly.md"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/nocodb/decree/cron.example/nocodb-db-backup-weekly.md
    dst: services/nocodb/decree/cron/
    label: "nocodb: db-backup-weekly.md"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/nocodb/decree/cron.example/nocodb-volume-backup-nightly.md
    dst: services/nocodb/decree/cron/
    label: "nocodb: volume-backup-nightly.md"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/nocodb/decree/cron.example/nocodb-volume-backup-weekly.md
    dst: services/nocodb/decree/cron/
    label: "nocodb: volume-backup-weekly.md"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/appsmith/decree/cron.example/appsmith-volume-backup-nightly.md
    dst: services/appsmith/decree/cron/
    label: "appsmith: volume-backup-nightly.md"
    requires: EXIST_IS_SERVICES_APPSMITH
  - src: services/appsmith/decree/cron.example/appsmith-volume-backup-weekly.md
    dst: services/appsmith/decree/cron/
    label: "appsmith: volume-backup-weekly.md"
    requires: EXIST_IS_SERVICES_APPSMITH
  - src: services/lowcoder/decree/cron.example/lowcoder-db-backup-nightly.md
    dst: services/lowcoder/decree/cron/
    label: "lowcoder: db-backup-nightly.md"
    requires: EXIST_IS_SERVICES_LOWCODER
  - src: services/lowcoder/decree/cron.example/lowcoder-db-backup-weekly.md
    dst: services/lowcoder/decree/cron/
    label: "lowcoder: db-backup-weekly.md"
    requires: EXIST_IS_SERVICES_LOWCODER
  - src: services/lowcoder/decree/cron.example/lowcoder-volume-backup-nightly.md
    dst: services/lowcoder/decree/cron/
    label: "lowcoder: volume-backup-nightly.md"
    requires: EXIST_IS_SERVICES_LOWCODER
  - src: services/lowcoder/decree/cron.example/lowcoder-volume-backup-weekly.md
    dst: services/lowcoder/decree/cron/
    label: "lowcoder: volume-backup-weekly.md"
    requires: EXIST_IS_SERVICES_LOWCODER
---
