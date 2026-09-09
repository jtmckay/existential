---
name: Media & Files
tagline: Host your photos, files, and documents yourself
e2e: true
services:
  - var: EXIST_IS_SERVICES_IMMICH
    label: Immich
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_NAS_REDIS
    label: Redis (Nextcloud cache — required by Nextcloud)
  - var: EXIST_IS_NAS_SEAWEEDFS
    label: SeaweedFS
  - var: EXIST_IS_NAS_COLLABORA
    label: Collabora
---
