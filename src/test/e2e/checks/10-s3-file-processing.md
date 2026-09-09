---
routine: e2e-s3-file-processing
e2e_check: 10-s3-file-processing
requires: EXIST_IS_NAS_SEAWEEDFS EXIST_IS_SERVICES_AUTOMATION
needs_routines: s3-router file-processor
---

Object written to seaweedfs → filer webhook → automation-webhook → inbox →
s3-router → file-processor → the processor actually runs.

This is the chain no per-service `exist.test.sh` can see. Every service was
individually healthy the whole time minIO was posting its events to port 48880,
which nothing listened on — decree's own test probed 8801 and passed, because it
was asking the one side that was never wrong. The question this asks is the one
a user actually cares about: if I drop a file in, does the thing happen?

It runs as a decree routine rather than a host script because everything it
needs is inside decree already: `rclone` is in the image
(`services/automation/decree/Dockerfile`), the object store's credentials are in
its compose environment as `S3_*`, `/repo` is mounted read-only, and it shares
the `exist` bridge with every service. The host-side version had to `docker
exec` into the store for each step.

The number is a sort key among checks, nothing more. Checks used to be staged
as migrations, where the prefix decided whether a probe ran before or after the
product's own 10-14 ollama pulls; they are inbox messages now, dropped after the
health gate, so ordering is `drop_checks`'s read order and the prefix only keeps
this file next to its siblings.

Three pieces stay on the host in `stage_checks`, because they are read at boot
and so cannot be changed by something the daemon is already running: the shipped
example file-processor, copied in as the probe; the webhook's `rclone_prefix`;
and the probe bucket's entry in `notification.toml`'s `path_prefixes`. That last
one is new under seaweedfs — minIO let a bucket subscribe itself at runtime with
one `mc event add`, but seaweedfs filters by filer path in a file read at boot,
so the probe bucket has to be named there before the stack comes up.
