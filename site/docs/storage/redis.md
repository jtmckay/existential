---
sidebar_position: 4
---

# Redis

- Source: https://github.com/redis/redis
- License: [BSD-3](https://opensource.org/licenses/BSD-3-Clause) (v7.2 and earlier) / RSALv2 + SSPLv1 (v7.4-7.x) / tri-licensed [RSALv2 / SSPLv1 / AGPLv3](https://redis.io/legal/licenses/) (v8+, the bundled `redis:alpine`). For commercial hosting, select AGPLv3 or RSALv2.
- Alternatives: Valkey, Dragonfly, Memcached

In-memory database used for caching and message queuing.

To avoid network traffic/delays, run Redis on the same server as the containers that require it (one instance per server).

