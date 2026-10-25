---
machine: nextcloud_calendar
---

Install and enable Nextcloud's Calendar app, so `https://nextcloud.<domain>/apps/calendar`
works and each user gets a "Personal" calendar (plus an auto-maintained "Contact birthdays"
calendar once Contacts has any birthdays in it).

The CalDAV backend (the `dav` app) ships enabled regardless — this only turns on the app that
puts a UI and calendar-specific endpoints in front of it.

Nextcloud admin credentials come from the decree container's own environment (rendered from
`nas/nextcloud/.env`) — nothing to set here.

Safe to re-run — install/enable is a no-op once the app is already there.

Requires nas/nextcloud (`EXIST_IS_NAS_NEXTCLOUD`) enabled.

Its flow's `calendar-extract.md` cron pulls events into `workspace/ai/calendar/`, where
OpenViking indexes them and hermes can answer questions about your calendar the same way it
answers anything else in `workspace/`.

`./existential.sh flow on calendar` activates it.
