---
machine: plugin
automation: workspace-agent
project: automation
name: Workspace agent
tagline: A file you save that matches your criteria is handed to an agent, and its answer lands in ai/
docs: /docs/decree/file-change-processing
services:
  - EXIST_IS_AI_QMD
  - EXIST_IS_AI_FIRECRAWL
needs:
  - agent_handoff
  - nextcloud-capture
---

CRITERIA in the processor (lib: file-processors/agent-handoff.sh of
automation/plugins/flows/agent_handoff.md) is the whole judgment: the shipped one looks for
unresolved questions. It is code, so it is changed there, on the host, and ./existential.sh
installs it; nothing in the workspace can.
