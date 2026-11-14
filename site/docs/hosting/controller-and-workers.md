---
sidebar_position: 13
---

# Controller and Workers

One host keeps your notes; the others just need watching. A **worker** is a host that runs decree
itself, with the `worker` flow on. Every 5 minutes it reports its free disk space, CPU, RAM and
VRAM use, the decree machines and plugins it has installed and the containers it runs to one Loki, and ships every decree run there
as it happens. Grafana's **Hosts** dashboard shows the hosts, and **Decree Overview** every run.

- The **controller** is the one host the others ask "where do I report?". It answers with a
  Loki's address. It is a worker too, with `EXIST_CONTROLLER` blank.
- Every other worker names it in `EXIST_CONTROLLER`.
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

## Add a worker

On the new host:

1. **Get the tools**, only if the host has neither docker nor podman (with either, skip this:
   the stack brings its own). `./existential.sh` checks for each and prints how to install
   what's missing:

   | Tool | For |
   |---|---|
   | `curl` | sends the reports, and installs decree and yq, so it comes first |
   | [decree](https://github.com/jtmckay/decree) | runs the worker's reporting: `curl -fsSL https://raw.githubusercontent.com/jtmckay/decree/main/install.sh \| sh` |
   | [yq](https://github.com/mikefarah/yq) v4 (mikefarah's, not the Python one) | installs the plugins |
   | `tmux` | keeps the decree daemon running |

   decree and yq install to `~/.local/bin`. If that isn't on your `PATH`, `./existential.sh`
   prints the line that puts it there, e.g.
   `echo 'export PATH="/home/you/.local/bin:$PATH"' >> ~/.bashrc`.

   Every worker, docker or not, also needs [alloy](https://github.com/grafana/alloy) on the
   host: it ships the decree runs. `./existential.sh` prints how to get it, the version the
   stack's own `loki-alloy` runs, into `~/.local/bin`.

2. **Clone and run.**

   ```bash
   git clone https://github.com/jtmckay/existential && cd existential
   ./existential.sh
   ```

   Pick **Worker**, then give the controller's tailnet name or 100.x address. A host with no
   docker or podman is not asked which: it can only be a worker, and goes straight to the
   controller question. A worker set up this way has no services: nothing runs in containers.

3. **Start [the host daemon](./host-daemon.md)**, and have it start at boot:

   ```bash
   tmux new -d -s existential-host -c "$PWD/host" decree daemon
   ```

4. **Check it's reporting.** Within 5 minutes, `./existential.sh` prints what the newest report
   said, as `Last report:`. So does the run's own log, `host/.decree/runs/<run>/0001-report.log`.

   | It says | Which means |
   |---|---|
   | `<hostname> to http://…: 1 disks, {"cpu_pct":…}, 1 machines, runs shipped live by alloy …` | Sent. The host is on the **Hosts** dashboard, and in Grafana's Explore as `{job="exist", host="<hostname>"}`; its runs are on **Decree Overview**. |
   | `no Loki named yet …, so nothing is sent` | The controller didn't answer, or names no Loki. Re-run `./existential.sh`: it warns when `http://<controller>:4480` doesn't answer. |
   | `none yet` | No report has run. If that lasts past 5 minutes, the host daemon isn't running. |

To name the controller later, or change it, edit the `EXIST_CONTROLLER=` line already in
`.env.shared` (only the first one is read). The next report uses it: nothing to restart.

Tailscale isn't checked: the worker only has to reach `http://<controller>:4480` and the Loki it
names. Both are served on the controller's tailnet, so in practice that's Tailscale.

### A host that already runs services

`./existential.sh flow on worker`, set `EXIST_CONTROLLER=<controller>` in `.env.shared`, then
steps 3 and 4.

## Without Tailscale: your own network

When every host is on one network, that network is already private and nothing more is needed:
no tailnet, no DNS record, no controller to ask. Loki listens there instead, and each host is told
where it is.

On the host with Loki, set `LOKI_BIND=0.0.0.0` in `hosting/loki/.env`, then `./existential.sh`
and `docker compose up -d`. Loki's push address is now `http://<that-host's-ip>:43100`.

Every other host follows [Add a worker](#add-a-worker) with one difference in step 2: press Enter
at the controller question, leaving `EXIST_CONTROLLER` blank, and name the Loki in `.env.shared`
(add the line if it isn't there):

```bash
EXIST_REPORTING_URL=http://192.168.1.10:43100   # the Loki host's address
```

## Updating on its own

A worker's decree daemon can also keep the install current: `./existential.sh flow on
auto-update` runs `git pull`, `./existential.sh` and `docker compose up -d` every 15 minutes.
On a host with neither docker nor podman, `flow` works the same, with the host's own tools,
and the update leaves out `docker compose`. See [Updates](./updates.md).

## What each host reports

The `reporting` plugin sends one push to Loki every 5 minutes, labelled `job="exist"` and
`host=<hostname>`:

| `kind` | One line per |
|---|---|
| `disk` | disk: `/` and each mount under `/mnt` (`/var/mnt` on an atomic host), its size and free space |
| `load` | push: average CPU % since the last one, RAM used and total, and GPU VRAM used and total, summed over every GPU, when there is one |
| `machine` | decree machine installed, in each project on the host (`automation`, `automation-backup`, `host`) |
| `plugin` | plugin installed, in each of those projects: the ones turned on and the ones they need |
| `container` | container running, by name and image (docker or podman, when the host has one) |

A container in the last day's reports that is missing from the last 10 minutes', on a host still
reporting, sends one ntfy notification: Grafana's `container stopped` alert, on the controller.

Each report also makes sure alloy is shipping this host's decree runs to that Loki, in a tmux
session, `reporting-alloy` (`tmux attach -t reporting-alloy` shows it): every step of every run
in `automation`, `automation-backup` and `host/.decree`, as `{job="decree"}`, and each script's
output, as `{job="decree_script"}`, labelled with `host` and `project` ([Loki](./loki.md)). It
keeps its place in each run's files, so a run that ends while it is down, or while the Loki is
away, is sent once it is back, within the 7 days Loki accepts. A new Loki address restarts it.

When the controller can't be reached, a worker uses the Loki it named last time. With no Loki
named anywhere, nothing is sent and nothing fails.

## Things to know

- **Loki has no login.** Anyone on your tailnet, and with `LOKI_BIND=0.0.0.0` anyone on your
  network, can push to it and read every log it holds, which includes every container's output.
  Use Tailscale's access controls, or a firewall rule for port 43100, to narrow it.
- **An install from before this page** has Loki's compose file already rendered without the
  loopback port. Add `ports: ["${LOKI_BIND:-127.0.0.1}:43100:3100"]` to the `loki` service in
  `hosting/loki/docker-compose.yml`, or `./existential.sh reset`, then re-run.
