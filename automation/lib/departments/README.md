# departments

**A department is a file here.** Adding one is adding a file — the same move this
repo makes for services, flows, cron jobs and e2e checks. Nothing enumerates them.

A department is what one [pi](https://pi.dev) run may reach: its built-in tools and
its MCP servers. `pi_run` (`../pi.sh`) turns the file into pi's `--tools` list, so a
department that owns no tool pays for none in its prompt.

## The file

`<name>.yml`, three flat keys, all optional except `description`:

```yaml
description: When work should come here — the router reads this to choose.
tools: read, grep, find, ls
mcp: openviking, firecrawl
```

`description` is the router's catalog entry, so write it as the answer to *"when
should work come here?"* rather than as a job title. `tools` are pi's built-ins
(`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`); `mcp` names servers
`pi_configure` registers: `openviking`, `firecrawl`, `playwright`, `qmd`, each only
while its add-on is on. Blank means none.

No department at all (`agent_task` without `department`) is pi's default tools plus
every MCP server.

## Who reads it

| Reader | For |
|---|---|
| `pi_run` (`../pi.sh`) | the tools and servers of one run |
| `router` | the catalog it chooses from |

## Using one

```
---
machine: agent_task
params:
  department: research
  output_name: competition
---
<the task>
```

`router` emits exactly that message after picking a department. Setup and reference:
<https://existential.company/docs/decree/routing>.
