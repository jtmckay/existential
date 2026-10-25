---
name: Workspace agent
tagline: A file you save that matches your criteria is handed to an agent, and its answer lands in ai/
docs: /docs/decree/file-change-processing
services:
  - EXIST_IS_AI_HERMES
  - EXIST_IS_AI_OPENVIKING
  - EXIST_IS_AI_FIRECRAWL
flows:
  - nextcloud-capture
processors:
  - agent-handoff.sh
---

CRITERIA in automation/lib/file-processors/agent-handoff.sh is the whole judgment: the
shipped one looks for unresolved questions. Rewrite it for what you want chased down.
