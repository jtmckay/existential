# nextcloud_richdocuments

Install richdocuments and point it at Collabora, with the WOPI allowlist set to the exist bridge.

Machine: [machines/nextcloud_richdocuments.yml](../machines/nextcloud_richdocuments.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_nextcloud
    nextcloud_richdocuments --> done: done
    nextcloud_richdocuments --> failed: error (implicit)
    wait_for_nextcloud --> nextcloud_richdocuments: done
    wait_for_nextcloud --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
