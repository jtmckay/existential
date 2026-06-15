---
cron: "0 8 * * *"
routine: check-disabled-runs
---

Check the last 24 hours of run directories for cron triggers that fired but
produced no routine.log — meaning the routine was disabled when the cron fired.
Exits non-zero to surface the failure in the dashboard.

Copy to decree/cron/ to activate.
