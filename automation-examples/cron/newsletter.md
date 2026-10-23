---
cron: "0 7 * * MON"
machine: newsletter
---

This week's issue: new items from `automation/lib/newsletter/feeds.txt`, picked
and summarised by the chat model against `automation/lib/newsletter/taste.md`,
written to `workspace/newsletter/<date>.md` with a notification of its first lines.

Edit taste.md — it is the whole judgment. A link is never sent twice: the
machine's store (volumes/workspace_data/.decree/store/newsletter/seen.tsv) remembers every one.

Copy to volumes/workspace_data/.decree/cron/ and restart automation to activate. To write an issue now:

  docker exec automation decree emit --machine newsletter </dev/null
