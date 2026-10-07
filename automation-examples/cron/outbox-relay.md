---
cron: "* * * * *"
routine: outbox-relay
---

Relay every message an agent dropped in `workspace/outbox/` into decree's inbox,
then delete it. The one door from workspace/ into decree for an agent that has
no mount into automation/.

Copy to automation/cron/ and restart automation to activate.
