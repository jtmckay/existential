---
name: Image OCR
tagline: Extract text from images dropped into Nextcloud or sent via Telegram
e2e: false
services:
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama
  - var: EXIST_IS_NAS_SEAWEEDFS
    label: SeaweedFS
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

Drop an image into Nextcloud (or send one to your Telegram bot) and Decree
runs OCR via an Ollama vision model, saving the extracted text next to the
original file.

The pipeline:
  Image synced to Nextcloud → seaweedfs file event
    → POST http://automation-webhook:8801/s3  (pre-configured in notification.toml)
    → s3-router matches PATTERN against the rclone path
    → ollama-ocr.sh: PATTERN='\.(jpg|jpeg|png|webp|gif|heic|heif|tiff?|bmp)$'
    → IS_PRE_SIGNED=false — image downloaded locally, base64-encoded, sent to Ollama
    → OCR text saved to same rclone path + ".ocr.txt" suffix

Processor convention (ollama-ocr.sh):
  PATTERN       matches common image formats
  IS_PRE_SIGNED false — file is downloaded to a temp path; Ollama reads base64
  FILE_SUFFIX   output filename suffix (default: .ocr.txt)
  OUTPUT_RCLONE rclone remote to write the text (default: nextcloud)
  OCR_MODEL     Ollama vision model to use (default: EXIST_MODEL_VISION)
  OLLAMA_URL    Ollama API base URL (default: http://ollama:11434)
  PROMPT        optional system prompt to guide extraction (default: auto)

Setup:
  1. Enable the routines in services/automation/decree/config.yml:
       file-processor:
         enabled: true
       s3-router:
         enabled: true

  2. Make sure the vision model is pulled in Ollama. It is chosen globally as
     EXIST_MODEL_VISION in .env.shared, and migration 14 pulls it for you:
       cp automation-examples/migrations/14-ollama-pull-vision-model.md \
          automation/migrations/
     Or pull it by hand:
       docker exec ollama ollama pull "$(grep ^EXIST_MODEL_VISION= .env.shared | cut -d= -f2)"

  3. Copy the processor in. Processor scripts are bind-mounted live into
     decree — no restart needed for this one:
       cp automation/lib/file-processors.example/ollama-ocr.sh \
          automation/lib/file-processors/

  4. Restart decree to pick up config changes:
       docker compose restart automation

  5. Nothing to subscribe. The webhook is declared once in
     nas/seaweedfs/notification.toml and read at boot, and it already covers the
     whole nextcloud bucket:
       endpoint      = "http://automation-webhook:8801/s3"
       path_prefixes = ["/buckets/nextcloud"]

     Using a DIFFERENT bucket? Add it to path_prefixes and restart seaweedfs —
     that file is the only place a bucket is subscribed.

Telegram OCR flow:
  If the auto-telegram quest is active, photos sent to your Telegram bot are
  already ingested into the bucket by telegram-poll. The ollama-ocr processor picks
  them up automatically — no extra steps.

Logs for each run land in automation/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
