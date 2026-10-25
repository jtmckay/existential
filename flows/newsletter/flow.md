---
name: Your own newsletter
tagline: Mondays, at most seven items from only the feeds you picked, judged by a paragraph you wrote
docs: /docs/flows/newsletter
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
---

List your feeds in automation/lib/newsletter/feeds.txt and say what you care about in
automation/lib/newsletter/taste.md. To write an issue now:
  echo | docker exec -i automation decree emit --machine newsletter
