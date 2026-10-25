---
name: Search
tagline: Your notes, PDFs and Word files, by meaning and by exact words, from Claude or a terminal
docs: /docs/ai/qmd
services:
  - EXIST_IS_AI_QMD
  - EXIST_IS_SERVICES_CODE_SERVER
e2e: true
---

After docker compose up -d, recreate code-server so Claude and opencode get the search
tool: docker compose up -d --force-recreate code-server. The first start downloads the
embedding model (about 320 MB) and indexes the workspace. Check it: ./existential.sh run qmd test
