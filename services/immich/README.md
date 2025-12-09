# Immich

- Source: https://github.com/immich-app/immich
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: PhotoPrism, Ente Photos, LibrePhotos, Photoview, Nextcloud Photos

## Features

- **Self-Hosted Library**: Private, high-performance photo and video library intended as a self-hosted Google Photos–style solution.
- **Automatic Mobile Backup**: Native Android/iOS apps for background backups with basic controls (e.g., Wi‑Fi-only).
- **Smart Search & AI**: Face recognition, object detection, and metadata-based search to quickly find photos.
- **Albums & Sharing**: Albums, shared albums, and public links for viewing, with normal use focused on browsing rather than editing.
- **Multi-User Support**: Multiple accounts with access controls so family or friends can browse shared collections.

### Getting started

Recommended to use on a machine you are already using Nextcloud as a client, so you can piggy back off of the file updates, and you don't have to do something way more complicated. This will use its own network "existAlt." Run `docker-compose up` within the immich directory itself after running `./existential.sh` to get your `.env` file.
