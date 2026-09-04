---
name: File Change Processing
tagline: React to files being created or updated in MinIO S3 storage
e2e: false
services:
  - var: EXIST_IS_NAS_MINIO
    label: MinIO
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

When a file lands in MinIO, the webhook triggers minio-router, which reads
every script in automation/lib/file-processors/, tests each PATTERN against
the file's rclone path, and fans out one file-processor job per match.

The pipeline:
  MinIO upload
    → POST http://automation-webhook:8801/minio  (pre-configured in MinIO compose)
    → minio-router reads lib/file-processors/*.sh, matches PATTERN
    → enqueues file-processor for each match
    → file-processor downloads the file (or gets a pre-signed URL)
    → runs the matching processor script

Processor convention — each script in automation/lib/file-processors/ declares:

  PATTERN="<bash-extended-regex>"
    Matched against the full rclone path: "<rclone_src>:<bucket>/<object-key>"
    Example: "nextcloud:.*\\.mp3$"

  IS_PRE_SIGNED=true|false
    true  — skip local download; minio-router generates a signed URL instead.
            Good for large files (audio, video) passed by URL to an API.
    false — download to a temp file at FILE_PATH; processor reads from disk.

Env vars available inside every processor script:
  FILE_SOURCE    full rclone path       e.g. "nextcloud:uploads/doc.pdf"
  FILE_KEY       path after "remote:"   e.g. "uploads/doc.pdf"
  FILE_ACTION    "created" or "removed"
  FILE_PATH      local temp path        (empty when IS_PRE_SIGNED=true)
  PRE_SIGNED_URL signed URL             (empty when IS_PRE_SIGNED=false)

All patterns are non-exclusive — multiple processors can match one file.
Temp files are deleted automatically after the processor exits.

Setup:
  1. Enable the routines in services/automation/decree/config.yml:
       file-processor:
         enabled: true
       minio-router:
         enabled: true

  2. Copy the example processor, rename it, and edit PATTERN + logic for
     your use case:
       cp automation/lib/file-processors.example/example.sh \
          automation/lib/file-processors/my-processor.sh

  3. Restart decree to pick up config changes:
       docker compose restart automation
     (processor scripts are bind-mounted live — no restart needed for those)

  4. Drop a file into MinIO and watch automation/runs/ for the run log.

Transcription and OCR have their own auto quests with ready-made processors.
