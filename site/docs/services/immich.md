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

## Containers

| Container | Role |
|---|---|
| `immich-server` | API, plus the "microservices" background-job workers (thumbnails, EXIF, transcode) — one combined Node process |
| `immich-machine-learning` | CLIP smart search, facial recognition, OCR — a separate FastAPI process the server calls per job |
| `immich-postgres` | Postgres + the `vchord` vector extension (`ghcr.io/immich-app/postgres:*-vectorchord*`) — a stock `pgvector` image cannot serve immich's indexes |
| `immich-redis` | Job queue (imports, thumbnails) — Valkey, no persisted data |

`immich-machine-learning` failing is invisible from `immich-server`'s own health: the API keeps
answering `/api/server/ping` and jobs that need the ML worker just fail one at a time with
"fetch failed" in the server's logs. `./existential.sh run immich test` probes it directly.

## GPU acceleration

`immich-machine-learning` ships a **different image tag per backend** (unlike ollama/whisperx,
there's no single binary that runtime-detects the card), wired the same way as every GPU
service in this stack via [`EXIST_GPU_VENDOR`](../configuration#gpu-vendor). The nvidia
`-cuda` tag is the default; a non-nvidia `EXIST_GPU_VENDOR` swaps in the `-rocm` tag (AMD, group
+ device passthrough — no `-cuda`-sized download you can't use) or the plain CPU tag (`none`).
Image sizes, for context: CPU 1.85 GB, `-cuda` 7.71 GB, `-rocm` 31.7 GB.

Hardware-accelerated *video transcoding* (`immich-server`, not the ML worker) is a separate,
manual opt-in — see the commented `extends: hwaccel.transcoding.yml` block in
`docker-compose.exist.yml`. It isn't vendor-wired: NVENC/VAAPI need a different capability set
than the ML reservation, and software transcoding already works with no extra setup.

## Access

`https://immich.<domain>` (Caddy) or `http://immich-server:2283` on the `exist` network.
`immich-machine-learning` is internal only — no Caddy hostname.

## Notes

**Version.** `IMMICH_VERSION` in `.env` defaults to `v3`, matching upstream's own current
default. The server only talks to the matching major version of the mobile app — don't jump
this ahead of what your phones have installed, and see
[immich's upgrade guide](https://docs.immich.app/install/upgrading) before crossing a major
version on an existing install (a fresh install has no such constraint).

**Storage paths are raw host paths, not `x-exist-volumes`.** `UPLOAD_LOCATION` (your photo
library) and `DB_DATA_LOCATION` (the Postgres data dir) live in `.env` under their upstream
names — that file is `convention-exempt: upstream-env`, so `generate-compose.ts` can't see them
by the usual bare-name mechanism. `exist.initial.sh` creates both, host-owned, before `docker
compose up` can create them as root (which breaks Postgres' first `initdb` and the ML model
cache). `UPLOAD_LOCATION` is bulk user data — point it at NFS if you like; `DB_DATA_LOCATION`
must stay local (Postgres, never NFS).

**Backup.** Copy `immich-db-backup-{nightly,weekly}.md` and
`immich-volume-backup-{nightly,weekly}.md` from `services/decree/decree-backup/cron.example/`
into `cron/` and restart `decree-backup`. The volume backup only reaches the default
`UPLOAD_LOCATION` (`./volumes/immich_library`) — `decree-backup` mounts the repo's `volumes/`
directory wholesale, so a library moved to NFS or another host path falls outside it and needs
its own backup story (the cron skips cleanly rather than failing).

**Containers run as the host user** (`EXIST_PUID`/`EXIST_PGID`), including `immich-server` and
`immich-machine-learning` — both images run root by default but need no capability it grants;
this was verified end to end (upload → thumbnail → EXIF → CLIP → face pipeline) as a non-root
user against a freshly-created library directory.
