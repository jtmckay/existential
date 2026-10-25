---
name: Look back
tagline: A week and a month in review, next to your notes, for when someone asks what you did
docs: /docs/getting-started#look-back
flows:
  - you-were-here
default: true
---

Sunday evenings for the week, the last evening of each month for the month. For a
year, ask: echo | docker exec -i automation decree emit --machine look_back --param period=year
