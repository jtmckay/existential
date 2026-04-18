---
sidebar_position: 6
---

# Cloudflare

- Source: https://cloudflare.com (managed service)
- Alternatives: Let's Encrypt + self-hosted DNS, Bunny DNS, Route 53

DNS and domain management for external access.

## DNS

Set up services you want exposed to the internet:

- Cloudflare proxy (your home external IP is not exposed)
- Cloudflare Origin Certificate (see below)
- By specific subdomain, or [wildcard](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-subdomain/)

## SSL Certificate

### Set SSL/TLS encryption

1. Go to SSL/TLS for your domain
2. Set encryption to **Full (strict)**

### Generate an Origin Certificate

1. Go to the dashboard → ellipses for your domain → Configure SSL/TLS
2. Under SSL/TLS → Origin server → Create Certificate
3. Use defaults & 15 years
4. Save the cert to `./cloudflare.pem` and key to `./cloudflare-key.pem`
