# Caddy
Reverse proxy

## Why?
So you can access everything hosted on different machines and ports, through a single externally accessible port (like one exposed with Ngrok).

### Costly lesson
Ports exposed to the docker host by using port: 8421:80 binds the host port to the docker port at :80 but, if another container within the docker network is accessing that container, it will still be :80 and not :8421.
