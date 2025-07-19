# NAS

Pick and choose the components to use. EG: use GoogleDrive for files, and skip TrueNAS, MinIO, Redis, and Nextcloud.

### What's important is to have the interface:
- NFS for container persistence
- S3 API for file persistence
- Nextcloud then gives the benefit of desktop and mobile app file sync (image/video upload etc.)

## File redundancy
- [TrueNAS](./trueNAS.md)

## File API
- [MinIO](../nas/minIO/README.md) (alt: AWS S3)

## Cache
- [Redis](../nas/redis/README.md)

## File sharing
- [Nextcloud](../nas/nextcloud/README.md) (managed alt: Dropbox/Onedrive/Google Drive)
