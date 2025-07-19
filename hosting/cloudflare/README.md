# Cloudflare
## DNS
Any services you want exposed to the internet will need to be setup/exposed.

One option is to set it up with:
- Cloudflare proxy (your home external IP is not exposed)
- Cloudflare Origin Certificate (below).
- By specific subdomain, or wildcard https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-subdomain/

## Certificate
### Set SSL/TLS encryption
- Go to the SSL/TLS for your domain
- Configure SSL/TLS encryption
- Set it to Full (strict)

### Generate an Origin certificate
- Go to the dashboard
- Click on the ellipses for your domain
- Configure SSL/TLS
- Under SSL/TLS on the left, select Origin server
- Click Create Certificate (defaults & 15 years is fine)
- Save the cert and key to `./cloudflare.pem` and `./cloudflare-key.pem` respectively
