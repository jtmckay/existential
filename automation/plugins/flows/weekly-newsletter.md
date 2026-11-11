---
machine: plugin
automation: weekly-newsletter
name: Your own newsletter
tagline: Mondays, at most seven items from only the feeds you picked, judged by a paragraph you wrote
docs: /docs/flows/newsletter
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
needs:
  - newsletter
cron:
  newsletter: |
    ---
    cron: "0 7 * * MON"
    machine: newsletter
    ---

    This week's issue: new items from `workspace/.decree/lib/newsletter/feeds.txt`, picked
    and summarised by the chat model against `workspace/.decree/lib/newsletter/taste.md`,
    written to `workspace/newsletter/<date>.md` with a notification of its first lines.

    Edit taste.md — it is the whole judgment. A link is never sent twice: the
    machine's store (volumes/workspace_data/.decree/store/newsletter/seen.tsv) remembers every one.

    `./existential.sh flow on weekly-newsletter` activates it. To write an issue now:

      docker exec automation decree emit --machine newsletter </dev/null
---

List your feeds in workspace/.decree/lib/newsletter/feeds.txt and say what you care about in
workspace/.decree/lib/newsletter/taste.md. To write an issue now:
  echo | docker exec -i automation decree emit --machine newsletter
