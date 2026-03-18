Configure remote fileshare

```
mkdir -p rclone
docker run --rm -it -v ./rclone:/config/rclone:Z rclone/rclone:latest config
```
