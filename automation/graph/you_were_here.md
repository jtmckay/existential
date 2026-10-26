# you_were_here

The "you were here" digest, written to workspace/ai/you-were-here.md and today's archive, pushed through ntfy when something changed.

Machine: [machines/you_were_here.yml](../machines/you_were_here.yml)

```mermaid
stateDiagram-v2
    [*] --> digest
    digest --> done: done
    digest --> failed: error (implicit)
    done --> [*]
    failed --> [*]
    note left of digest
        store: feeds-shown.tsv, learn-shown.tsv, state.json
    end note
```
