---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  hermes_agent_data hermes-agent
---

Weekly tar of hermes_agent_data volume (retained 28 days).

Copy to decree/cron/ to activate.
