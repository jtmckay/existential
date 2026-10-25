---
name: Your calendar, readable by agents
tagline: Nextcloud's calendar app on, and every event mirrored into the workspace as a note
docs: /docs/storage/nextcloud
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
---

Set CALENDAR_EXTRACT_TZ in volumes/workspace_data/.decree/cron/calendar-extract.md to
your own zone (e.g. America/Denver) so times read right.
