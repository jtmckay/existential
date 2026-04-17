# Setup

## Configure remote fileshare

Add Nextcloud/WebDAV, Dropbox, or whatever file sharing solutions you want to use.

```
mkdir -p secrets/rclone
docker run --rm -it --network host -v ./secrets/rclone:/config/rclone:Z $(docker build -q .) rclone config
```

## Configure S3

# Run decree

#### Connect to shell (currently running)

```
docker compose run decree bash
```

#### One off (if it isn't currently running with daemon)

```
docker compose run --rm decree decree process
```
