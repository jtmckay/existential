# Docker
https://github.com/docker/compose

### Setup network for all containers to use
```bash
docker network create \
  --driver overlay \
  --attachable \            # lets ‘stand-alone’ compose containers join, too
  --opt encrypted \         # IP-sec between nodes
  exist                     # must match the name in your compose files
```
