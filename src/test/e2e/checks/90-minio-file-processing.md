---
routine: e2e-minio-file-processing
e2e_check: 90-minio-file-processing
requires: EXIST_IS_NAS_MINIO EXIST_IS_SERVICES_DECREE
needs_routines: minio-router file-processor
---

Object written to MinIO → S3 event → decree-webhook → inbox → minio-router →
file-processor → the processor actually runs.

This is the chain no per-service `exist.test.sh` can see. Every service was
individually healthy the whole time MinIO was posting its events to port 48880,
which nothing listened on — decree's own test probed 8801 and passed, because it
was asking the one side that was never wrong. The question this asks is the one
a user actually cares about: if I drop a file in, does the thing happen?

It runs as a decree routine rather than a host script because everything it
needs is inside decree already: `mc` and `rclone` are in the image
(`automations/Dockerfile`), MinIO's credentials are in its compose environment,
`/repo` is mounted read-only, and it shares the `exist` bridge with every
service. The host-side version had to `docker exec` into MinIO for each step.

Numbered `90-` so it lands after the product's own migrations (10-14 ollama,
20-22 minio): those create the buckets and pull the models, and a probe that
halted the pass would take them with it.

Two pieces stay on the host in `stage_checks`, because they are read at boot and
so cannot be changed by something the daemon is already running: the shipped
example file-processor, copied in as the probe, and the webhook's
`rclone_prefix`.
