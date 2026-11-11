---
machine: plugin
automation: calendar
name: Your calendar, readable by agents
tagline: Nextcloud's calendar app on, and every event mirrored into the workspace as a note
docs: /docs/storage/nextcloud
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - calendar_extract
  - nextcloud_calendar
cron:
  calendar-extract: |
    ---
    cron: "*/30 * * * *"
    machine: calendar_extract
    params:
      CALENDAR_EXTRACT_PAST_DAYS: 7
      CALENDAR_EXTRACT_FUTURE_DAYS: 60
      CALENDAR_EXTRACT_TZ: UTC
    ---

    Every 30 minutes, mirrors every Nextcloud calendar you have (Personal, Contact birthdays, any
    shared calendar) into `workspace/ai/calendar/<calendar>/` as one markdown note per event — recent
    past through `CALENDAR_EXTRACT_FUTURE_DAYS` ahead. Those notes are indexed by
    qmd (the `search` flow) the same as anything else in `workspace/`, which is what lets
    pi actually answer "what's on my calendar" instead of you having to open Nextcloud.

    Full-mirror, not append-only: an event that's cancelled, deleted, or ages out the back of the
    window has its note removed on the next run — the directory always reflects what's really
    scheduled right now, not everything that was ever synced.

    Set `CALENDAR_EXTRACT_TZ` to your own IANA zone (e.g. `America/Denver`) so the human-readable
    "When:" line in each note matches your wall clock — the frontmatter's `start`/`end` stay UTC
    either way. `CALENDAR_EXTRACT_CALENDARS` restricts which calendars are pulled (comma-separated
    slugs, e.g. `personal`) if you'd rather skip "Contact birthdays".

    Requires nas/nextcloud (`EXIST_IS_NAS_NEXTCLOUD`) enabled, and the Calendar app installed —
    the calendar flow's `24-nextcloud-calendar.md` migration does that once.

    `./existential.sh flow on calendar` activates it.
migrations:
  24-nextcloud-calendar: |
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
    qmd indexes them and pi can answer questions about your calendar the same way it
    answers anything else in `workspace/`.

    `./existential.sh flow on calendar` activates it.
---

Set CALENDAR_EXTRACT_TZ in volumes/workspace_data/.decree/cron/calendar-extract.md to
your own zone (e.g. America/Denver) so times read right.
