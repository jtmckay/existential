# Caddy

https://github.com/caddyserver/caddy

Reverse proxy

## Why?

So you can access everything hosted on different machines and ports, through a single externally accessible port (like one exposed with Ngrok).

### Costly lesson

Ports exposed to the docker host by using port: 8421:80 binds the host port to the docker port at :80 but, if another container within the docker network is accessing that container, it will still be :80 and not :8421.

### Privileged port error
Change the kernel setting to let unprivileged users bind to lower ports like 80 by adding this line to `/etc/sysctl.conf`:
`net.ipv4.ip_unprivileged_port_start=80`
Then apply it immediately with:

`sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80`
