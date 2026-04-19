---
sidebar_position: 5
---

# Ngrok

- Source: https://github.com/ngrok/ngrok (CLI open source; service is proprietary)
- License: [MIT](https://opensource.org/licenses/MIT) (CLI)
- Alternatives: Cloudflare Tunnel, Tailscale, localtunnel, bore
- Status: Unnecessary with VPN

Punches a hole to the internet, allowing access to a specific port on your machine from anywhere without port forwarding on your router.

## Features

- **Instant HTTPS Tunnels**: Expose any local port with a public HTTPS URL in one command
- **Request Inspection**: Built-in dashboard to inspect and replay incoming HTTP requests
- **TLS Termination**: Handles SSL certificates automatically
- **TCP & TLS Tunnels**: Supports non-HTTP protocols (SSH, databases, etc.)
- **Custom Subdomains**: Stable URLs on paid plans (random URLs on free tier)

```bash
ngrok http 80

# Generate run command from env vars
source .env && echo "ngrok http --url=$NGROK_URL $PORT"
```
