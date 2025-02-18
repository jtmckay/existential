# Collabora
https://github.com/CollaboraOnline/online

Live collaborative editor like you would get with google docs, libre office, or office 365.

## Domain setup
Setup your Domain DNS server to point the subdomain `collabora` to Caddy, and ensure Caddy is pointing here.

## Setup with Nextcloud
- In Nextcloud
- Apps
- Search for Nextcloud Office (NOT Collabora Online - Built-in CODE Server)
- Install it
- Go to settings
- Set "Use your own server"
- Value: `https://collabora.example.com`

### Ensure trusted proxies covers Collabora
- Nextcloud trusted proxies should cover an IP range EG: ..0.0/12
- Collabora should have a static IP of ..0.8
