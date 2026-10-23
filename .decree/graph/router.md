# router

Ask Claude to pick one of the options in the request.

Machine: [machines/router.yml](../machines/router.yml)

```mermaid
stateDiagram-v2
    [*] --> ask
    ask --> done: done
    ask --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
