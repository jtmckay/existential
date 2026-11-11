---
machine: plugin
automation: code-server-agents
name: Agents in code-server
tagline: claude, opencode and pi in code-server's terminal, pi on the stack's own model
docs: /docs/services/code-server
services:
  - EXIST_IS_SERVICES_CODE_SERVER
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - pi
  - capture
  - capture-stream
---

code-server reads pi and capture from the workspace's decree project, where these
plugins install them.
