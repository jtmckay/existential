---
service: hosting/fleet-api
sidebar_position: 12
---

# Fleet API

- Source: https://github.com/jtmckay/decree-go-rest
- Port: `:8801`, on the network, behind the fleet secret

A GPU box's lease API: [decree-go-rest](../plugins/http.md), pulled as an image, in front of the
box's own decree project (the checkout's `.decree`). Another host's fleet lib asks it for the
card (`POST /gpu/<mode>/<client>`), and the box's `lease_gpu`, in its
[host daemon](./host-daemon.md), carries the lease out. It runs no work itself and can write
nothing but `.decree/inbox/`.

Only a GPU box runs it, and a GPU box is host-wired by choice: `lease_gpu` starts and stops the
box's GPU processes, so it needs the host daemon. The controller never runs it; its API is the
[model gateway](../ai/model-gateway.md).

## Turn it on

On the GPU box:

```bash
./existential.sh run fleet api
```

That turns the service on (`EXIST_IS_HOSTING_FLEET_API=true`), writes its config once
(`.decree/decree-go-rest.yml`, the box's own, to which each host plugin adds its endpoints) and
starts it. It is `restart: unless-stopped`, so it comes back with the container engine after a
reboot. A box set up before this, which started decree-go-rest from `.decree/boot.sh`, has that
line, its tmux session and its container taken away by the same command.

After a new fleet secret (`./existential.sh run fleet join`), it is recreated so it takes it.

## Check it

```bash
./existential.sh test fleet-api      # /healthz, and a lease without the secret refused
docker logs fleet-api
```

Telemetry: none; it sends nothing anywhere.
