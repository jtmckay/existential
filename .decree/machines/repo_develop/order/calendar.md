---
machine: repo_develop
---
# Your calendar, readable by agents

## Overview

An agent that can't see the calendar plans in a vacuum. Nextcloud's calendar is mirrored into
the workspace as plain notes, where search and every agent already look.

## Outcome

- `nextcloud_calendar` installs and enables Nextcloud's Calendar app (an order, run once).
- `calendar_extract` mirrors the events in a window around today into `workspace/ai/calendar/`,
  one note per event, in the time zone `CALENDAR_EXTRACT_TZ` in its cron file.
- Guide: *Everything in One Place*, Email and calendar.

## Constraints

- It writes only under `workspace/ai/`; it never changes the calendar.

## Acceptance Criteria

- **Given** `./existential.sh validate conventions`
  **Then** it passes: `plugin on calendar_extract` is on a docs page
