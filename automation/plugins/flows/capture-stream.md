---
name: capture-stream
x-exist-project: automation
x-exist-title: Capture
x-exist-tagline: What you type to an agent, and anything you POST, in one stream in workspace/.capture/
x-exist-docs: /docs/getting-started#capture
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - capture
---

POST /capture on automation-webhook appends to the stream; code-server's agents append
every prompt you type, secrets redacted.
