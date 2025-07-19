# Portainer
https://github.com/portainer/portainer

Works with a single machine running docker, a multi-server setup with Docker Swarm, or K8s etc. We will use Docker Swarm, as it can still be setup on a single server, but allows the flexibility to expand.

## Deployment
Must be done from a manager node in the docker swarm.

`docker stack deploy -c docker-compose.yml portainer`
