---
sidebar_position: 4
---

# Portainer

- Source: https://github.com/portainer/portainer
- License: [zlib](https://github.com/portainer/portainer/blob/develop/LICENSE) (Community Edition)
- Alternatives: Dockge, Yacht, Lazydocker
- UI: `https://portainer.<domain>`
- Credentials: `admin` / `EXIST_PASSWORD` (seeded once, at first boot — see below)

Remote Docker container management. Portainer itself also supports Docker Swarm and
Kubernetes, but in this stack it runs as an ordinary compose service on a single host.

## The privilege is real, and `:ro` doesn't change that

Portainer mounts `/var/run/docker.sock` (`:ro` — see below) so it can drive the Docker daemon:
list, create, start, stop and delete anything, on any container. That is root-equivalent on
the host: anyone who can log into Portainer can start a privileged container that bind-mounts
`/` and own the machine. Treat the admin password as a root password, and don't expose
`portainer.<domain>` beyond the LAN/Tailscale.

The socket is mounted **read-only**, and that is worth being precise about: it is not a
security boundary. Verified directly — authenticating and then issuing a real
`POST .../docker/containers/create` through Portainer's API, against a `:ro`-mounted socket,
still created a container on the host. A `:ro` bind mount only stops the *container* from
unlinking or replacing the socket file; every read/write privilege the connection carries is
enforced by `dockerd` on the other end, not by the mount flag. It's mounted `:ro` anyway
because it costs nothing and is what Portainer's own packaging does (its Docker Desktop
extension's bundled compose file, baked into the image, mounts the same path `:ro`) — but
nothing here narrows what a compromised Portainer container can do to the host.

Portainer's container also runs as **root**, unavoidably: the image ships no `USER` (defaults
to uid/gid 0) and is fully distroless — no shell, no package manager, no way to add a user to
the host's `docker` group even if the image weren't already root. There is no least-privilege
knob to turn here; root is the only identity this image can run as, and the socket it needs is
root-equivalent regardless of which uid asks it for something.

## The admin password is a one-time seed

`portainer_password.txt` is rendered once from the shared `EXIST_PASSWORD` and mounted
read-only; `--admin-password-file` points the distroless entrypoint at it (it ships no shell,
so nothing can be written into the container at startup any other way). Verified via the
container's own logs: this only takes effect on the **very first boot**, while no admin user
exists yet. Every boot after that logs `instance already has an administrator user defined,
skipping admin password related flags` and never reads the file again.

Two consequences:

- Rotating `EXIST_PASSWORD` later does nothing here — the rendered file doesn't even
  re-render (`templates.sh` renders each destination once), and even if it did, Portainer would
  ignore it past the first boot.
- A password changed through the Portainer UI survives every restart, untouched.

There is also no in-image way to reset a forgotten admin password — no shell to exec into, no
CLI subcommand for it. The only recovery path is deleting the `portainer_data` volume (which
also discards every environment/setting Portainer has stored) and letting first-boot seeding
run again.

## No native healthcheck

The image ships no shell, `wget` or `curl`, and the `portainer` binary has no self-probe flag
— there is no `CMD` a Docker `HEALTHCHECK` could exec inside the container, so this service
doesn't define one. `exist.test.sh` covers it instead: an external HTTP probe of `/api/status`,
plus a real login with the seeded credentials and a check that Portainer's own view of the
local Docker environment reports up.

## Deployment

Enable it and bring the stack up from the repo root like any other service:

```bash
EXIST_IS_HOSTING_PORTAINER=true    # in .env.shared
./existential.sh && docker compose up -d
```
