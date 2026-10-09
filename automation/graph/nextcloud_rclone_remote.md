# nextcloud_rclone_remote

Configure the nextcloud rclone remote (WebDAV, admin credentials) that file_processor downloads through.

Machine: [machines/nextcloud_rclone_remote.yml](../machines/nextcloud_rclone_remote.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_nextcloud
    nextcloud_rclone_remote --> done: done
    nextcloud_rclone_remote --> failed: error (implicit)
    wait_for_nextcloud --> nextcloud_rclone_remote: done
    wait_for_nextcloud --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
