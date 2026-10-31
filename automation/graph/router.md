# router

Ask the chat model which department fits a task, then hand it to agent_task in that department.

Machine: [machines/router.yml](../machines/router.yml)

```mermaid
stateDiagram-v2
    [*] --> route
    route --> done: done
    route --> failed: error (implicit)
    route --> not_routed: not_routed
    done --> [*]
    failed --> [*]
    not_routed --> [*]
```
