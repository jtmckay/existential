---
name: notes-to-dropbox
x-exist-project: automation
x-exist-title: Notes to Dropbox
x-exist-tagline: Every 10 minutes, your Nextcloud notes compiled, indexed and pushed to Dropbox
x-exist-docs: /docs/integrations/rclone
x-exist-services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - notes
  - nextcloud-capture
cron:
  notes.md: |
    ---
    cron: "*/10 * * * *"
    machine: notes
    ---

    Notes compilation and sync.
---

Add the Dropbox remote once: ./existential.sh run rclone
