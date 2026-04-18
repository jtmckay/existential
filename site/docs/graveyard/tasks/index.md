---
sidebar_position: 1
---

# Task App Alternatives

## Checklist

- Recurring tasks
- Notifications

## Evaluated

- [Vikunja](../../services/vikunja) — active stack
- [ntfy](../../services/ntfy) — active stack (notifications)
- [Super Productivity](./super-productivity) — RIP unrecoverable sync issues on phone
- Notion
- Tasks.org
- Todoist
- TickTick

## Compromise: Tasker

Use [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=en_US) to open the task app every Nth time you unlock your phone (e.g., every 7th unlock):

1. Add var `%LastTaskOpen`
2. Create Profile → Event → Display → Display Unlocked
3. Add Action → Alert → Flash: "Launching app"
4. Add Action → App → Shortcut (use the deeplink from your task app)
5. Add if `%LastTaskOpen` ~ `0`
6. Add Action → Variables → Variable Add `%LastTaskOpen`
7. Add Action → Variables → Variable Set `%LastTaskOpen` to `0` if `%LastTaskOpen` > `6`
