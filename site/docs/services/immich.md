---
sidebar_position: 4
---

# Immich

- Source: https://github.com/immich-app/immich
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: PhotoPrism, Ente Photos, LibrePhotos, Photoview, Nextcloud Photos

## Getting Started

Immich is a [complementary service](../how-it-works#core-vs-complementary-services) — nothing else in the stack talks to it, so it can run on its own machine (or its own schedule) without affecting anything. Running it alongside Nextcloud lets it piggyback off the same file updates.

Immich is brought up from the repo root with everything else (`./existential.sh && docker compose up -d`). Being complementary means you *can* move it to another machine — not that it needs separate commands here.
