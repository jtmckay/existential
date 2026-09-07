---
cron: "*/30 * * * *"
routine: calendar-extract
CALENDAR_EXTRACT_PAST_DAYS: "7"
CALENDAR_EXTRACT_FUTURE_DAYS: "60"
CALENDAR_EXTRACT_TZ: "UTC"
---

Every 30 minutes, mirrors every Nextcloud calendar you have (Personal, Contact birthdays, any
shared calendar) into `workspace/ai/calendar/<calendar>/` as one markdown note per event — recent
past through `CALENDAR_EXTRACT_FUTURE_DAYS` ahead. Those notes are indexed by
`openviking-index-knowledgebase` the same as anything else in `workspace/`, which is what lets
hermes actually answer "what's on my calendar" instead of you having to open Nextcloud.

Full-mirror, not append-only: an event that's cancelled, deleted, or ages out the back of the
window has its note removed on the next run — the directory always reflects what's really
scheduled right now, not everything that was ever synced.

Set `CALENDAR_EXTRACT_TZ` to your own IANA zone (e.g. `America/Denver`) so the human-readable
"When:" line in each note matches your wall clock — the frontmatter's `start`/`end` stay UTC
either way. `CALENDAR_EXTRACT_CALENDARS` restricts which calendars are pulled (comma-separated
slugs, e.g. `personal`) if you'd rather skip "Contact birthdays".

Requires nas/nextcloud (`EXIST_IS_NAS_NEXTCLOUD`) enabled, and the Calendar app installed —
`automation-examples/migrations/24-nextcloud-calendar.md` does that once.

Copy to `automation/cron/` and restart `automation` to activate.
