---
machine: e2e_file_processing
e2e_check: 10-file-processing
requires: EXIST_IS_NAS_NEXTCLOUD EXIST_IS_SERVICES_AUTOMATION EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
---

File uploaded to Nextcloud → webhook_listeners → nextcloud-cron's worker →
automation-webhook → inbox → file_router → file_processor → the processor
actually runs.

This is the chain no per-service `exist.test.sh` can see. Every service can be
individually healthy while Nextcloud posts its events to a port nothing listens
on, or never posts them at all because nothing runs its background jobs. The
question this asks is the one a user actually cares about: if I drop a file in,
does the thing happen?

It runs as a decree machine rather than a host script because everything it
needs is inside decree already: `curl` and `jq` are in the image, the Nextcloud
admin credentials are in its compose environment, and it shares the `exist`
bridge with every service.

The webhook it probes is the one Nextcloud actually has registered — read back
from the webhook_listeners API, which the `nextcloud-file-events` migration
wrote — not one assumed here.

The number is a sort key among checks, nothing more. Checks are inbox messages
dropped after the health gate, so ordering is `drop_checks`'s read order and the
prefix only keeps this file next to its siblings.

One piece stays on the host in `stage_checks`: the shipped example
file-processor, copied in as the probe, because `lib/` is read-only inside the
daemon.
