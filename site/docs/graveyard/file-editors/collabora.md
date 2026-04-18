---
sidebar_position: 2
---

# Collabora

- Source: https://github.com/CollaboraOnline/online
- License: [MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)
- Alternatives: OnlyOffice, LibreOffice Online
- Status: RIP — clunky UI

Live collaborative editor like Google Docs / LibreOffice / Office 365, embedded in Nextcloud.

## Domain Setup

Point the `collabora` subdomain in your DNS to Caddy, and ensure Caddy proxies to the Collabora container.

## Setup with Nextcloud

1. In Nextcloud → Apps → search for **Nextcloud Office** (not "Collabora Online - Built-in CODE Server")
2. Install it
3. Go to Settings → Set "Use your own server"
4. Value: `https://collabora.example.com`

### Trusted Proxies

- Nextcloud trusted proxies should cover an IP range (e.g., `..0.0/12`)
- Collabora should have a static IP (e.g., `..0.8`)
