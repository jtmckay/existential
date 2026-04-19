---
sidebar_position: 4
---

# Redis

- Source: https://github.com/redis/redis
- License: [BSD-3](https://opensource.org/licenses/BSD-3-Clause) (v7.2 and earlier) / [RSALv2/SSPL](https://redis.io/legal/licenses/) (v7.4+)
- Alternatives: Valkey, Dragonfly, Memcached

In-memory database used for caching and message queuing.

To avoid network traffic/delays, run Redis on the same server as the containers that require it (one instance per server).

## Features

- **Sub-Millisecond Latency**: In-memory storage for extremely fast reads and writes
- **Rich Data Structures**: Strings, hashes, lists, sets, sorted sets, streams, and more
- **Pub/Sub Messaging**: Broadcast events to multiple subscribers in real time
- **Persistence**: RDB snapshots and AOF append-only log for crash recovery
- **Lua Scripting**: Atomic server-side scripts for complex operations
- **TTL & Eviction**: Per-key expiry for cache use cases with configurable eviction policies
