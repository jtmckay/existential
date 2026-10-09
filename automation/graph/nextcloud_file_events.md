# nextcloud_file_events

Register Nextcloud's file-event webhooks (written, deleted, renamed) against automation-webhook's /files.

Machine: [machines/nextcloud_file_events.yml](../machines/nextcloud_file_events.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_nextcloud
    nextcloud_file_events --> done: done
    nextcloud_file_events --> failed: error (implicit)
    wait_for_nextcloud --> nextcloud_file_events: done
    wait_for_nextcloud --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
