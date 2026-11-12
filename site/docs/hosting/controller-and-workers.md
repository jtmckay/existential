---
sidebar_position: 13
---

# Controller and Workers

One host keeps your notes; the others just need watching. A **worker** is a host that runs decree
itself, with the `worker` flow on. Every 5 minutes it reports its free disk space, the decree
machines it has installed and each one's runs to one Loki, and Grafana's **Hosts** dashboard
shows them all.

- A worker with `EXIST_CONTROLLER` set reports to that controller.
- A worker with it blank **is** the controller: the others ask it where to report.
- A host doesn't have to be a worker at all. Without the `worker` flow, nothing runs on the
  host and nothing is reported.

Every host is in one [Tailscale](https://tailscale.com) tailnet, as Core already needs.

## The controller

Pick **Controller** on the first run (or `./existential.sh flow on worker` later, with
`EXIST_CONTROLLER` blank), then turn on where the reports land:

```bash
./existential.sh service on loki grafana
./existential.sh
docker compose up -d
```

`./existential.sh` serves two things on the tailnet, plain http (WireGuard already encrypts the
traffic):

| Address | What it is |
|---|---|
| `http://<controller>:4480` | The answer to "where do I report?", `host/exist.json` |
| `http://<host>:3100` | Loki's push address, on whichever host has Loki on |

To report to a Loki on another host, set `EXIST_REPORTING_URL=http://<that-host>:3100` in the
controller's `.env.shared` and re-run `./existential.sh`. Every worker picks it up on its next
report.

## Every other host

```bash
git clone https://github.com/jtmckay/existential && cd existential
./existential.sh            # pick Worker, then give the controller's tailnet name or 100.x address
```

A worker picked on the first run has no services: nothing runs in containers. On a host that
already runs services, `./existential.sh flow on worker` and `EXIST_CONTROLLER=<controller>` in
`.env.shared` make it a worker too.

### What a worker needs

A worker needs no container engine and builds no image. Pick **Worker** on the first run, or run
a bare `./existential.sh` on a host with neither docker nor podman, where a worker is the one
thing it can be and nothing is asked. It asks the controller's address, turns every service off,
and installs the worker flow with the host's own tools. It checks for them first and, for each
one missing, prints how to install it:

| Tool | For |
|---|---|
| `curl` | sends the reports, and installs decree and yq, so it comes first |
| [decree](https://github.com/jtmckay/decree) | runs the worker's reporting: `curl -fsSL https://raw.githubusercontent.com/jtmckay/decree/main/install.sh \| sh` |
| [yq](https://github.com/mikefarah/yq) v4 (mikefarah's, not the Python one) | installs the plugins |
| `tmux` | keeps the decree daemon running |

decree and yq install to `~/.local/bin`. If that isn't on your `PATH`, `./existential.sh` prints
the line that puts it there, e.g. `echo 'export PATH="/home/you/.local/bin:$PATH"' >> ~/.bashrc`.

Tailscale isn't checked: the worker only has to reach `http://<controller>:4480` and the Loki it
names, and `./existential.sh` warns when the controller doesn't answer. Both are served on the
controller's tailnet, so in practice that's Tailscale.

Either way, the worker flow runs in the host's own decree project, `host/.decree`. Start its
daemon the way [Updates](./updates.md#a-decree-daemon-on-the-host) says, and have it start at
boot. Within 5 minutes the host is on the **Hosts** dashboard.

## Without Tailscale: your own network

When every host is on one network, that network is already private and nothing more is needed:
no tailnet, no DNS record. Loki listens there instead, and each host is told where it is.

On the host with Loki, set `LOKI_BIND=0.0.0.0` in `hosting/loki/.env`, then `./existential.sh`
and `docker compose up -d`. Loki's push address is now `http://<that-host's-ip>:43100`.

On every other host, leave `EXIST_CONTROLLER` blank and name the Loki
in `.env.shared`:

```bash
EXIST_REPORTING_URL=http://192.168.1.10:43100   # the Loki host's address
```

then `./existential.sh flow on worker` (or pick **Worker** on the first run and press Enter at
the controller question). Each host is its own controller, so none asks another where to report.

## Updating on its own

A worker's decree daemon can also keep the install current: `./existential.sh flow on
auto-update` runs `git pull`, `./existential.sh` and `docker compose up -d` every 15 minutes.
See [Updates](./updates.md).

## What each host reports

The `reporting` plugin sends one push to Loki every 5 minutes, labelled `job="exist"` and
`host=<hostname>`:

| `kind` | One line per |
|---|---|
| `disk` | real filesystem: mount, size and free space |
| `machine` | decree machine installed, in each project on the host (`automation`, `automation-backup`, `host`) |
| `run` | run that finished since the last push: its machine, final state, duration |

When the controller can't be reached, a worker uses the Loki it named last time. With no Loki
named anywhere, nothing is sent and nothing fails.

## Things to know

- **Loki has no login.** Anyone on your tailnet, and with `LOKI_BIND=0.0.0.0` anyone on your
  network, can push to it and read every log it holds, which includes every container's output.
  Use Tailscale's access controls, or a firewall rule for port 43100, to narrow it.
- **An install from before this page** has Loki's compose file already rendered without the
  loopback port. Add `ports: ["${LOKI_BIND:-127.0.0.1}:43100:3100"]` to the `loki` service in
  `hosting/loki/docker-compose.yml`, or `./existential.sh reset`, then re-run.
