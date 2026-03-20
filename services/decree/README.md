Configure remote fileshare

```
mkdir -p rclone
docker run --rm -it --network host -v ./rclone:/config/rclone:Z rclone/rclone:latest config
```

Run decree one off (if it isn't currently running with daemon)

```
docker compose run --rm decree decree process
```
