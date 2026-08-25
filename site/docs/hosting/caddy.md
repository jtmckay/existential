---
sidebar_position: 5
---

# Caddy

- Source: https://github.com/caddyserver/caddy
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Nginx, Traefik, Nginx Proxy Manager, HAProxy

Reverse proxy — access everything hosted on different machines and ports through a single externally accessible port.

## Port Binding Note

Ports exposed to the Docker host using `port: 8421:80` bind the host port to the Docker port at `:80`. However, if another container within the Docker network is accessing that container, it will still use `:80` — not `:8421`.

## Privileged Port Error

To allow binding to port 80 without root, add to `/etc/sysctl.conf`:

```
net.ipv4.ip_unprivileged_port_start=80
```

Apply immediately:

```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
```
