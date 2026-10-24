---
name: File Change Processing
tagline: React to files being created or updated in Nextcloud
e2e: false
services:
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
    label: automation-webhook (receives the POSTs)
---

When a file is uploaded to Nextcloud, its webhook triggers file-router, which
reads every script in automation/lib/file-processors/, tests each PATTERN
against the file's rclone path, and fans out one file-processor job per match.

The pipeline:
  Upload through Nextcloud (desktop client, web UI, WebDAV)
    → nextcloud-cron's worker POSTs http://automation-webhook:8801/files
      (registered by the 27-nextcloud-file-events migration)
    → file-router reads lib/file-processors/*.sh, matches PATTERN
    → enqueues file-processor for each match
    → file-processor downloads the file (or gets a pre-signed URL)
    → runs the matching processor script

Processor convention — each script in automation/lib/file-processors/ declares:

  PATTERN="<bash-extended-regex>"
    Matched against the full rclone path: "nextcloud:<path in Nextcloud>"
    Example: "nextcloud:.*\\.mp3$"

  IS_PRE_SIGNED=true|false
    true  — skip local download; file-processor generates a share link instead.
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

Only uploads THROUGH Nextcloud fire. Files hermes, code-server or decree write
straight into the workspace do not — that is what keeps an agent's own output
from triggering another run.

Setup:
  1. The **Capture** quest does this. By hand: copy
     automation-examples/migrations/23-nextcloud-rclone-remote.md and
     27-nextcloud-file-events.md into volumes/workspace_data/.decree/migrations/. file-router and
     file-processor are enabled by default.

  2. Copy the example processor, rename it, and edit PATTERN + logic for
     your use case:
       cp automation/lib/file-processors.example/example.sh \
          automation/lib/file-processors/my-processor.sh
     (processor scripts are bind-mounted live — no restart needed for those)

  3. Drop a file into Nextcloud and watch volumes/workspace_data/.decree/runs/ for the run log.

Transcription and OCR have their own auto quests with ready-made processors.
