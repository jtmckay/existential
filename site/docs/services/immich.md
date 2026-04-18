---
sidebar_position: 4
---

# Immich

- Source: https://github.com/immich-app/immich
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: PhotoPrism, Ente Photos, LibrePhotos, Photoview, Nextcloud Photos

## Features

- **Self-Hosted Library**: Private, high-performance photo and video library — a self-hosted Google Photos alternative
- **Automatic Mobile Backup**: Native Android/iOS apps for background backups with basic controls (e.g., Wi-Fi-only)
- **Smart Search & AI**: Face recognition, object detection, and metadata-based search to quickly find photos
- **Albums & Sharing**: Albums, shared albums, and public links for viewing
- **Multi-User Support**: Multiple accounts with access controls so family or friends can browse shared collections

## Getting Started

Recommended to use on a machine already running Nextcloud as a client, so you can piggyback off file updates. This uses its own network `existAlt`.

Run `docker-compose up` within the `immich` directory after running `./existential.sh` to get your `.env` file.
