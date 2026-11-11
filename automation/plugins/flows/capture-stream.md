---
machine: plugin
automation: capture-stream
name: Capture
tagline: What you type to an agent, and anything you POST, in one stream in workspace/.capture/
docs: /docs/getting-started#capture
services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - capture
---

POST /capture on automation-webhook appends to the stream; code-server's agents append
every prompt you type, secrets redacted.
