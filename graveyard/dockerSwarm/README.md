# RIP docker swarm networking was annoying and added complexity for env variables
# Docker Swarm
https://github.com/docker/compose

To manage multiple servers.

### Setup network
If the "exist" network already exists, delete it.
- run on every node that still has it
`docker network rm exist`
```bash
docker network create \
  --driver overlay \
  --attachable \            # lets ‘stand-alone’ compose containers join, too
  --opt encrypted \         # IP-sec between nodes
  exist                     # must match the name in your compose files
```

### Setup swarm (manager first)
https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/
- `docker swarm init --advertise-addr <MANAGER-IP>`
- Save the output to add a worker to the swarm. EG: "docker swarm join --token SmthnSprlng1 192.168.1.10:2377"

Deploy the registry Docker container. In the Docker directory:
`docker stack deploy -c docker-compose.yml registry`

### Join swarm (as worker)
- Run the command to join as a worker, returned from the ["Setup swarm"](./README.md#setup-swarm) step

### Setup a Docker registry
https://docs.docker.com/engine/swarm/stack-deploy/

### Pin service
##### Set node requirement in docker-compose:
```
deploy:
  placement:
    constraints:
      - node.labels.has_local_ssd == true
```

##### List swarm nodes
`docker node ls`

##### Label node with the requirement:
`docker node update --label-add has_local_ssd=true {hostname}`
