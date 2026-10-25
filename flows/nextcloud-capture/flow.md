---
name: Files from your phone start work
tagline: A file uploaded through Nextcloud runs every file processor whose pattern matches it
docs: /docs/decree/file-change-processing
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
---

Sync the workspace folder with the Nextcloud desktop client (nextcloud.com/install),
logging in at https://nextcloud.<domain> with the admin login in nas/nextcloud/.env.
Only uploads through Nextcloud fire; a file an agent writes straight to disk never does.
To write your own processor:
  cp automation/lib/file-processors.example/example.sh automation/lib/file-processors/<name>.sh
