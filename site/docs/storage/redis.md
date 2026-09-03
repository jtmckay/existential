---
sidebar_position: 4
---

# Redis

- Source: https://github.com/redis/redis
- License: [BSD-3](https://opensource.org/licenses/BSD-3-Clause) (v7.2 and earlier) / RSALv2 + SSPLv1 (v7.4-7.x) / tri-licensed [RSALv2 / SSPLv1 / AGPLv3](https://redis.io/legal/licenses/) (v8+, the pinned `redis:8.10.1-alpine3.23`). For commercial hosting, select AGPLv3 or RSALv2.
- Alternatives: Valkey, Dragonfly, Memcached

## Role

This instance backs [Nextcloud](./nextcloud) only. It is Nextcloud's `memcache.distributed`
and `memcache.locking` backend (transactional file locking, so two clients can't corrupt the
same file at once) and its PHP session store — both wired by the official `nextcloud` image
whenever `REDIS_HOST` is set (`redis.config.php`, `entrypoint.sh`'s `configure_redis_session`).
Nothing else in the stack talks to it.

Three other services bundle their own, separate Redis/Valkey instance instead of sharing this
one: `firecrawl-redis` (rate limiting/job state), `lowcoder-redis` (session/query cache), and
`immich-redis` (job queue). Enabling this service does not add caching to any of them.

## Auth

`--requirepass` is always on (`EXIST_REDIS_PASSWORD`). A bare `redis-cli ping` against it
returns `NOAUTH`, not `PONG` — pass `-a` (see `nas/redis/exist.test.sh` for a dependency-free
AUTH+PING check, and the healthcheck in `nas/redis/docker-compose.exist.yml`).

## Persistence

`volumes/redis_data` is a real, persisted volume (`db: true`) — RDB snapshots survive a
container restart, on redis's own default save schedule. No `maxmemory` or eviction policy is
set, so redis grows until it hits the container's memory limit rather than evicting old keys;
at that point Docker's OOM killer restarts it. There is no backup wired up for this volume.

To avoid network traffic/delays, run Redis on the same server as the containers that require it
(one instance per server).
