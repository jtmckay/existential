---
name: Notes to Dropbox
tagline: Every 10 minutes, your Nextcloud notes compiled, indexed and pushed to Dropbox
docs: /docs/integrations/rclone
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
flows:
  - nextcloud-capture
---

Add the Dropbox remote once: ./existential.sh run rclone
