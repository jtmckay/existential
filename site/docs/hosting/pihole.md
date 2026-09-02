---
sidebar_position: 12
---

# Pi-hole

- Source: https://github.com/pi-hole/pi-hole
- License: [EUPL-1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)
- UI: `https://pihole.<domain>`

Network-wide DNS ad blocker and optional DHCP server. Blocks ads, trackers, and malicious domains for all devices on the network by acting as the primary DNS resolver.

## Ports

| Service | Port |
|---|---|
| DNS | 53 (TCP + UDP) — published on the host |
| Web UI | 80, reached only through Caddy at `https://pihole.<domain>` |
| DHCP (optional) | 67 — uncomment in the compose template |
| NTP (optional) | 123 — uncomment in the compose template |

## Setup

1. Enable it in `.env.shared`:
   ```
   EXIST_IS_HOSTING_PIHOLE=true
   ```
2. Render and start, from the repo root:
   ```bash
   ./existential.sh && docker compose up -d
   ```
3. Point your router's DNS to the host running Pi-hole

Pi-hole then resolves the whole of `EXIST_DOMAIN` locally via a single wildcard record, which
removes the stack's dependency on public DNS. It is an upgrade, not a requirement — see
[How It Works](../how-it-works).

## Debugging

```bash
docker compose logs pihole
# Check DNS resolution
docker exec pihole nslookup example.com
```
