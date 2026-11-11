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

Either way, the worker flow runs in the host's own decree project, `host/.decree`. Start its
daemon the way [Updates](./updates.md#a-decree-daemon-on-the-host) says, and have it start at
boot. Within 5 minutes the host is on the **Hosts** dashboard.

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

- **Anyone on your tailnet can push to Loki.** That's the same trust as code-server on the
  tailnet; use Tailscale's access controls to narrow it.
- **An install from before this page** has Loki's compose file already rendered without the
  loopback port. Add `ports: ["127.0.0.1:43100:3100"]` to the `loki` service in
  `hosting/loki/docker-compose.yml`, or `./existential.sh reset`, then re-run.
