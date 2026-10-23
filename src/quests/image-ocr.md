---
name: Image OCR
tagline: Extract text from images dropped into Nextcloud or sent via Telegram
e2e: false
services:
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
done:
  files:
    - automation/lib/file-processors/ollama-ocr.sh
---

Drop an image into Nextcloud (or send one to your Telegram bot) and Decree
runs OCR via an Ollama vision model, saving the extracted text next to the
original file.

The pipeline:
  Image synced to Nextcloud → Nextcloud file event
    → POST http://automation-webhook:8801/files  (27-nextcloud-file-events migration)
    → file-router matches PATTERN against the rclone path
    → ollama-ocr.sh: PATTERN='\.(jpg|jpeg|png|webp|gif|heic|heif|tiff?|bmp)$'
    → IS_PRE_SIGNED=false — image downloaded locally, base64-encoded, sent to Ollama
    → OCR text saved to same rclone path + ".ocr.txt" suffix

Processor convention (ollama-ocr.sh):
  PATTERN       matches common image formats
  IS_PRE_SIGNED false — file is downloaded to a temp path and sent as base64
  FILE_SUFFIX   output filename suffix (default: .ocr.txt)
  OUTPUT_RCLONE rclone remote to write the text (default: nextcloud)
  OCR_MODEL     vision model to use (default: EXIST_MODEL_VISION)
                sent to EXIST_MODEL_URL_VISION, any OpenAI-compatible /v1 server
  PROMPT        optional system prompt to guide extraction (default: auto)

Setup:
  1. File events must be on — Core does it. By hand: copy
     automation-examples/migrations/23-nextcloud-rclone-remote.md and
     27-nextcloud-file-events.md into volumes/workspace_data/.decree/migrations/. file-router and
     file-processor are enabled by default.

  2. Make sure the vision model is pulled in Ollama. It is chosen globally as
     EXIST_MODEL_VISION in .env.shared, and migration 14 pulls it for you:
       cp automation-examples/migrations/14-ollama-pull-vision-model.md \
          volumes/workspace_data/.decree/migrations/
     Or pull it by hand:
       docker exec ollama ollama pull "$(grep ^EXIST_MODEL_VISION= .env.shared | cut -d= -f2)"

  3. Copy the processor in. Processor scripts are bind-mounted live into
     decree — no restart needed:
       cp automation/lib/file-processors.example/ollama-ocr.sh \
          automation/lib/file-processors/

Telegram OCR flow:
  If the Telegram Bot quest is active, photos sent to your Telegram bot are
  already uploaded into Nextcloud's telegram/ folder by telegram-poll. The ollama-ocr processor picks
  them up automatically — no extra steps.

Logs for each run land in volumes/workspace_data/.decree/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
