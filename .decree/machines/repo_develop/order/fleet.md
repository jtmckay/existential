---
machine: repo_develop
---
# More than one computer: a controller the others report to, and its GPUs shared

## Overview

Once there is a second computer, the person wants one place that shows every host and every
run, one model address that reaches whichever box has the GPU, and nothing new to babysit on
each host. Setup never makes this happen on its own: a fleet is chosen, one command per host.

## Outcome

- **The controller** is made by `./existential.sh run fleet controller`, never by the first run:
  the fleet secret, then Loki, Grafana and the model gateway, all containers, nothing on the
  host. It prints the join line, and, until it is done, the recommended second step: make it a
  worker too (`plugin on report_host`, `run host-daemon install`), whose `report_host` puts it on
  the Hosts dashboard, relays the other hosts' notifications to its ntfy (`notify-relay`) and
  pushes its answer (its domain) for workers on your own network.
- **A worker** is `./existential.sh run fleet join <controller's domain> [<secret>]`, or the first run's
  answer b: `report_host` and the host daemon, nothing in containers, so it needs no Docker.
  Every 5 minutes it reports disks, CPU, RAM, VRAM, machines, plugins, crons, containers and
  offers, and alloy ships every decree run live.
- **Where to report**: `https://model-gateway.<controller's domain>`, on any network: `EXIST_CONTROLLER`
  is the controller's domain, and the controller's Caddy hands it to the model gateway, which
  takes the fleet secret and fronts Loki, on loopback ([[networking]]). The controller is Loki,
  Grafana, the model gateway and Caddy (`run fleet controller`).
- **The model gateway** (`ai/model-gateway`) is one OpenAI-compatible `/v1` for every host:
  it leases whichever host offers the model a call names and streams its answer; it serves
  `/plugins/fleet_gpu.md`, the fleet lib as a plugin for a decree project of your own. It runs
  the fleet lib from the repo's plugin file, never the workspace's.
- **Offers and leases**: a GPU box offers what it serves through `report_host`; its lease API is
  `hosting/fleet-api` ([[gpu-box]]); `model_base`, `pi_run` and `comfy` lease through the
  `fleet` lib. `./existential.sh run peers` lists what every host offers.
- **Services a host has off** point at the controller's domain; ntfy alone becomes the
  controller's Loki push address, relayed, so no ntfy password leaves the controller.
- `run fleet status` says what a host is and whether its controller answers.
- The Technical page *Controller and Workers* covers all of it; the Guide only says a worker is
  for a second computer.

## Constraints

- Nothing on a host's own systemd, launchd or decree is set up without the person running a
  command that says so.
- Nothing a host sends the controller is plain HTTP: reports, runs, offers, notifications and
  model calls are HTTPS through its Caddy. A GPU box's lease API (`:8801`, host to host) is
  the one HTTP path, and the docs say so.
- Host code runs on bash 3.2 and BSD tools.

## Acceptance Criteria

- **Given** `./existential.sh test report-host`
  **Then** it exits 0
- **Given** `./existential.sh test model-gateway`
  **Then** it exits 0
- **Given** a first run answered with Enter
  **Then** Loki, Grafana and the model gateway are off and `.decree/plugins/.on` has no `report_host`
