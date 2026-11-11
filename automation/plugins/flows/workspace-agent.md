---
machine: plugin
automation: workspace-agent
name: Workspace agent
tagline: A file you save that matches your criteria is handed to an agent, and its answer lands in ai/
docs: /docs/decree/file-change-processing
services:
  - EXIST_IS_AI_OPENVIKING
  - EXIST_IS_AI_FIRECRAWL
needs:
  - agent_handoff
  - nextcloud-capture
---

CRITERIA in workspace/.decree/lib/file-processors/agent-handoff.sh (yours, copied once from
agent-handoff.exist.sh) is the whole judgment: the
shipped one looks for unresolved questions. Rewrite it for what you want chased down.
