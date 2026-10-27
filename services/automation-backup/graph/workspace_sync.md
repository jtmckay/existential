# workspace_sync

Two-way sync workspace/ with a folder in Nextcloud, skipping what any .gitignore ignores and every .git/, and asking a person before a large delete.

Machine: [machines/workspace_sync.yml](../machines/workspace_sync.yml)

```mermaid
stateDiagram-v2
    [*] --> sync
    confirm_deletes --> delete: delete (person)
    confirm_deletes --> failed: error (implicit)
    confirm_deletes --> keep: keep (person)
    delete --> done: done
    delete --> failed: error (implicit)
    keep --> done: done
    keep --> failed: error (implicit)
    sync --> done: done
    sync --> failed: error (implicit)
    sync --> confirm_deletes: too_many_deletes
    done --> [*]
    failed --> [*]
    note left of sync
        store: bisync, held, synced
    end note
    note right of confirm_deletes
        person: ask
    end note
```
