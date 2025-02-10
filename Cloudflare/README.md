# Cloudflare
## Certificate
### Generate an Origin certificate
- Go to the dashboard
- Click on the ellipses for your domain
- Configure SSL/TLS
- Under SSL/TLS on the left, select Origin server
- Click Create Certificate (defaults & 15 years is fine)
- Save the cert and key to `./cloudflare.pem` and `./cloudflare-key.pem` respectively
