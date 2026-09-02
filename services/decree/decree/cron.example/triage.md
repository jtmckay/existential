---
cron: "*/5 * * * *"
routine: triage
---

Runs every enabled service's own `exist.test.sh` and reports what is and is not
working. This is `./existential.sh test services`, run for you.

The 5-minute cron is a TICK, not the check interval. The routine decides whether
each tick is due: every consecutive all-green round pushes the next real check
further out (5 → 5 → 15 → 30 → 60 → 360 minutes), and any failure drops it back
to the tightest interval. A stack that comes up clean is checked a few times and
then left alone; a stack that does not stays under close watch until it is.

Notifications fire on CHANGE only — a service breaking, or recovering. A service
that has been failing since yesterday does not page you again.

Nothing is configured per service. Enablement comes from .env.shared, so a
service you add tomorrow is triaged tomorrow with no cron file to write. That is
the difference between this and `service-health`, which probes one URL you named.

Where to look:
  docker exec decree cat /data/triage/status.md    the plain-language answer
  docker logs decree                               the run, with failing lines
  Grafana                                          exist_service_healthy per service

Tuning (add as frontmatter keys above):
  TRIAGE_BACKOFF        minutes per step, default "5 5 15 30 60"
  TRIAGE_MAX_INTERVAL   the interval it settles to, default 360
  TRIAGE_NOTIFY         false to stop ntfy notifications entirely
  TRIAGE_ALWAYS         true to check every tick and ignore the backoff
  TRIAGE_STRICT         true to exit non-zero when a service is failing.
                        Leave it off here: decree would retry the whole suite
                        and dead-letter it. e2e sets it, because there the exit
                        code is the verdict.
