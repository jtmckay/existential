---
name: code-server-agents
x-exist-project: automation
x-exist-title: Agents in code-server
x-exist-tagline: claude, opencode and pi in code-server's terminal, pi on the stack's own model
x-exist-docs: /docs/services/code-server
x-exist-services:
  - EXIST_IS_SERVICES_CODE_SERVER
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - pi
  - capture
  - capture-stream
---

code-server reads pi and capture from the workspace's decree project, where these
plugins install them.
