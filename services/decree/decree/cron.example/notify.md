---
cron: "0 9 * * 1"
routine: notify
ntfy_topic: 'exist'
ntfy_title: 'Weekly reminder'
ntfy_priority: 'default'
ntfy_tags: 'calendar'
---

Replace this body with the notification message to send on the cron schedule.
ntfy_topic defaults to "decree" if not set; override with ntfy_topic in frontmatter.

Copy to decree/cron/ and set the cron schedule and message body to activate.
