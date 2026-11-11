---
machine: plugin
automation: notes-to-dropbox
name: Notes to Dropbox
tagline: Every 10 minutes, your Nextcloud notes compiled, indexed and pushed to Dropbox
docs: /docs/integrations/rclone
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - notes
  - nextcloud-capture
cron:
  notes: |
    ---
    cron: "*/10 * * * *"
    machine: notes
    ---

    Notes compilation and sync.
---

Add the Dropbox remote once: ./existential.sh run rclone
