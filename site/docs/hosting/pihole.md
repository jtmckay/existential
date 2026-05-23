---
sidebar_position: 12
---

# Pi-hole

- Source: https://github.com/pi-hole/pi-hole
- License: [EUPL-1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)
- UI: `http://localhost:42480`

Network-wide DNS ad blocker and optional DHCP server. Blocks ads, trackers, and malicious domains for all devices on the network by acting as the primary DNS resolver.

## Ports

| Service | Port |
|---|---|
| DNS | 53 (TCP + UDP) |
| Web UI | 42480 (HTTP), 42443 (HTTPS) |
| DHCP (optional) | 67 |
| NTP (optional) | 123 |

## Setup

1. Copy `.env.example` to `.env`
2. `docker compose up -d`
3. Point your router's DNS to the host running Pi-hole

## Debugging

```bash
docker compose logs pihole
# Check DNS resolution
docker exec pihole nslookup example.com
```
