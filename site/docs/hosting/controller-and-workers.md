---
sidebar_position: 13
---

# Controller and Workers

One host keeps your notes; the others just need watching. A **worker** is a host that runs decree
itself, with `report_host` on. Every 5 minutes it reports its free disk space, CPU, RAM and
VRAM use, the decree machines and plugins it has installed and the containers it runs to one Loki, and ships every decree run there
as it happens. Grafana's **Hosts** dashboard shows the hosts, and **Decree Overview** every run.

- The **controller** is the one host the others report to: its Loki holds the reports, and its
  Caddy is the one way in, over HTTPS. It is usually a worker too, with `EXIST_CONTROLLER` blank
  and Loki on. A host with `EXIST_CONTROLLER` blank and no Loki reports nowhere.
- Every other worker names the controller's domain (its `EXIST_DOMAIN`) in `EXIST_CONTROLLER`,
  and reports to `https://model-gateway.<that domain>`.
- A host doesn't have to be a worker at all. Without `report_host`, nothing runs on the
  host and nothing is reported.

Any network works, your own or a [Tailscale](https://tailscale.com) tailnet: every worker only
has to resolve and reach the controller's `<slug>.<domain>` names ([Networking](../networking.md)).

## Set up the controller

Setup never makes a controller. Pick the computer that stays on (usually the one running Core)
and, after its first run:

### 1. Make it the controller

```bash
./existential.sh run fleet controller
docker compose up -d
```

This makes the fleet secret and turns on where the reports land, Loki and Grafana, with the
[model gateway](../ai/model-gateway.md), the fleet's API, and [Caddy](./caddy.md), the way in.
All four are containers: nothing is set up on the host itself, no systemd unit and no host
daemon. It prints the line each worker joins with.

Every worker has to trust the controller's certificate. With a certificate of your own (a
domain you own, [Networking](../networking.md)) there is nothing to do. With the one Caddy
makes, signed by the controller's own CA, `fleet controller` says so: install
`hosting/caddy/certs/internal-ca.pem` on every worker first (the Caddyfile's header has the
command for each system).

### 2. Make it a worker too (recommended)

```bash
./existential.sh plugin on report_host
./existential.sh run host-daemon install
```

Most controllers want this. Its own `report_host` is what:

- puts the controller itself on the **Hosts** dashboard and ships its own decree runs;
- relays the other hosts' notifications to its ntfy (`notify-relay`, [below](#services-a-host-has-off)).

It is a separate step because it runs on the host: the [host daemon](./host-daemon.md) is a
systemd user unit (a LaunchAgent on a Mac) running decree outside any container. Skip it and
the controller still collects every other host's reports.

The controller's Caddy serves one name to the other hosts, `https://model-gateway.<domain>`, the
model gateway, which asks for the fleet secret:

| Path | What it is |
|---|---|
| `/loki/api/v1/…` | The controller's Loki: reports, decree runs, offers and notifications are pushed here, and offers read back |
| `/v1` | The fleet's models |
| `/plugins/fleet_gpu.md` | The `fleet_gpu` plugin |

Loki itself has no login and listens only on the controller's loopback; the gateway hands on
only Loki's push and query paths.

## Services a host has off

On every other host, each `./existential.sh` makes any address in `.env` that names the
container of a service that is off on that host point at the controller's domain
(`EXIST_CONTROLLER`) instead: `EXIST_MODEL_URL=http://ollama:11434/v1` becomes
`https://ollama.<domain>/v1`. An address you set to anything else is left alone. The
controller's Caddy (or yours) has to serve each of those names.

Notifications are the exception, so no ntfy password leaves the controller. On a host with ntfy
off, `EXIST_NTFY_URL` becomes the controller's Loki (`https://model-gateway.<domain>/loki/api/v1/push`),
`notify` pushes each message there as `{job="exist", kind="notify"}`, and the controller,
with ntfy on, publishes it to ntfy within 15 seconds. That relay runs in the controller's tmux
session `notify-relay` (`tmux attach -t notify-relay`), started by its `report_host`, and needs
`jq` on the controller. It keeps its place, so a message sent while it is down goes out once it
is back.

## Add a worker

A worker is another computer of yours that reports to the controller: its disks, CPU, RAM and
VRAM, what it runs, and every decree run. It runs nothing in containers, so it needs no Docker.
The whole setup is one command and a few Enters.

### 1. Clone and run

On the new computer:

```bash
git clone https://github.com/jtmckay/existential && cd existential
./existential.sh
```

### 2. Answer the questions

```
What is this computer?
  a) Core: your editor, notifications, automation and search (default)
  b) A worker: it reports this host to a controller, and runs nothing else
a or b [a]: b
Which host is the controller? This worker sends its reports there, over HTTPS.
Controller: home.example.com
```

Give the controller's domain, `EXIST_DOMAIN` in its `.env.shared`, not its address. A computer with neither docker
nor podman isn't asked the first question: it can only be a worker. Every answer is kept as soon
as you give it, so nothing is asked twice, even if setup stops halfway.

### 3. Let it install what's missing

A worker runs its reporting with its own tools. Whatever is missing is offered in one go, with
the commands shown; Enter runs them:

```
  Missing here: decree yq tmux alloy. Install now? This runs:
       curl -fsSL https://github.com/jtmckay/decree/releases/download/v0.6.1/install.sh | sh -s -- v0.6.1
       mkdir -p ~/.local/bin && curl -fsSL -o ~/.local/bin/yq https://github.com/mikefarah/yq/…
       sudo apt-get install -y tmux
       …
  Install [Y/n]:
```

| Tool | For |
|---|---|
| `curl` | sends the reports, and installs the others, so it comes first |
| [decree](https://github.com/jtmckay/decree) | runs `report_host`, the plugin that reports |
| [yq](https://github.com/mikefarah/yq) v4 (mikefarah's, not the Python one) | installs the plugins |
| `tmux` | keeps the daemon running |
| [alloy](https://github.com/grafana/alloy) | ships the decree runs; without it reports still send |

decree, yq and alloy go to `~/.local/bin` without sudo; `tmux` and `curl` come from your package
manager, through `sudo`, which asks for your password. If `~/.local/bin` isn't on your `PATH`,
the run prints the line that adds it. Without a terminal, or on `n`, the commands are printed
for you to run, then `./existential.sh` again.

### 4. Start the daemon, now and at every boot

The reports come from a decree daemon on the worker itself. The run offers to start it:

```
  The host's plugins (report_host) run in a decree daemon on the host, and none runs here.
  This starts it now, and at every boot (a systemd user unit; a LaunchAgent on a Mac).
  Start it [Y/n]:
```

Enter installs it into systemd (details on [the host daemon](./host-daemon.md#start-it)): a user
unit, `~/.config/systemd/user/existential-host.service`, enabled and started, with linger on so it
starts at boot before anyone logs in. Turning linger on can take root; if it does, the run asks
before it runs `sudo loginctl enable-linger`. To do it later, or again after moving the checkout:

```bash
./existential.sh run host-daemon install
```

### 5. Check it's reporting

Every run ends with where the worker stands:

```
This worker:
  ✓ reports to https://model-gateway.home.example.com
  ✓ ships its decree runs (alloy)
  ✓ running (tmux attach -t existential-host)
  ✓ starts at boot (systemd user unit)
  ✓ linger on: before anyone logs in
  Last report: myworker to https://model-gateway.home.example.com: 1 disks, {"cpu_pct":…}, 1 machines, runs shipped live by alloy
```

`./existential.sh run host-daemon status` prints the same at any time. The first report comes
within 5 minutes of the daemon starting.

| `Last report:` says | Which means |
|---|---|
| `<hostname> to https://…: 1 disks, {"cpu_pct":…}, …` | Sent. The host is on the controller's **Hosts** dashboard, and in Grafana's Explore as `{job="exist", host="<hostname>"}`; its runs are on **Decree Overview**. |
| `no controller named …, so nothing is sent` | `EXIST_CONTROLLER` is blank. Set it to the controller's domain. |
| `EXIST_CONTROLLER=… is an address` | It names the controller by IP, as before reports went over HTTPS. Set it to the controller's domain. |
| a failed run, `curl: (60)` | The worker doesn't trust the controller's certificate: install its CA ([Set up the controller](#1-make-it-the-controller)). |
| a failed run, `401` | The worker's `EXIST_FLEET_SECRET` isn't the controller's. |
| nothing at all | No report has run yet. If that lasts past 5 minutes, the daemon isn't running: `./existential.sh run host-daemon status` says why. |

To name the controller later, or change it, edit the `EXIST_CONTROLLER=` line already in
`.env.shared` (only the first one is read). The next report uses it: nothing to restart.

`./existential.sh run fleet status` asks `https://model-gateway.<controller's domain>` with this host's
secret, and says whether it answers.

### A host that already runs services

`./existential.sh plugin on report_host`, set `EXIST_CONTROLLER=<controller's domain>` in `.env.shared`, then
`./existential.sh run host-daemon install` and step 5.

## The fleet command

`./existential.sh run fleet` does all of the above, plus the fleet secret and the host daemon, in
one command per host. Run it again any time; it changes only what is missing:

```bash
./existential.sh run fleet controller                          # on the controller: prints the join line
./existential.sh run fleet join <controller's domain> <secret> # on every other host, after ./existential.sh
./existential.sh run fleet api                                 # on a GPU box: its lease API, the fleet-api container
./existential.sh run fleet status                              # on any host: controller, secret, daemon, last report
```

By hand: on the controller, turn on Loki, Grafana, the model gateway and Caddy
(`./existential.sh service on loki grafana model-gateway caddy`), set `EXIST_FLEET_SECRET` in
`.env.shared`, then `./existential.sh` and `docker compose up -d`. Every other host follows
[Add a worker](#add-a-worker), with the same `EXIST_FLEET_SECRET` (`fleet join` sets it); without
it the gateway turns its reports away.

## Updating on its own

A worker's decree daemon can also keep the install current: `./existential.sh plugin on
pull_existential` runs `git pull`, `./existential.sh` and `docker compose up -d` every 15 minutes.
On a host with neither docker nor podman, `plugin` works the same, with the host's own tools,
and the update leaves out `docker compose`. See [Updates](./updates.md).

## What each host reports

The `report_host` plugin sends one push to Loki every 5 minutes, labelled `job="exist"` and
`host=<hostname>`:

| `kind` | One line per |
|---|---|
| `disk` | disk: `/` and each mount under `/mnt` (`/var/mnt` on an atomic host), its size and free space |
| `load` | push: average CPU % since the last one, RAM used and total, and GPU VRAM used and total, summed over every GPU, when there is one |
| `machine` | decree machine installed, in each project on the host (`automation`, `automation-backup`, `host`) |
| `plugin` | plugin installed, in each of those projects: the ones turned on and the ones they need |
| `cron` | active cron (`cron/`) in each of those projects, with its schedule and machine |
| `container` | container running that is meant to stay up, by name and image (docker or podman, when the host has one): one with a restart policy, as every service has, or the label `exist.watch=true`; never an adhoc run, a `docker run --rm`, or one labelled `exist.watch=false` (Strata, which comes and goes with its lease) |
| `offer` | service a host plugin offers the other hosts, and how to lease it ([Peers](#peers-what-the-other-hosts-offer)) |

A container in the last day's reports that is missing from the last 10 minutes', on a host still
reporting, sends one ntfy notification on the `host` topic: Grafana's `container stopped` alert, on the controller.

Each report also makes sure alloy is shipping this host's decree runs to that Loki, in a tmux
session, `reporting-alloy` (`tmux attach -t reporting-alloy` shows it): every step of every run
in `automation`, `automation-backup` and the host's project (the checkout's `.decree`), as `{job="decree"}`, and each script's
output, as `{job="decree_script"}`, labelled with `host` and `project` ([Loki](./loki.md)). It
keeps its place in each run's files, so a run that ends while it is down, or while the Loki is
away, is sent once it is back, within the 7 days Loki accepts. A new Loki address restarts it.

When the controller can't be reached, the report fails and the next one tries again; alloy
sends the runs it missed once it is back. With no controller named, nothing is sent and nothing
fails.

## Peers: what the other hosts offer

Every host knows its controller, so every host can ask it what the others offer. A host plugin
that serves something to the others says so in each report (`kind="offer"`): the
[AI box](./ai-box.md)'s llama.cpp, ComfyUI and TTS, with the address of the lease each needs.
Any host reads the latest offers back from the Loki its controller names:

```bash
./existential.sh run peers            # every host's offers, from the last 15 minutes
./existential.sh run peers llm        # one service
./existential.sh run peers --json     # the same, for a script
```

```text
<ai-box>         comfy    http://<ai-box>:8188                     lease http://<ai-box>:<port>/gpu/comfy/<client>
<ai-box>         llm      http://<ai-box>:8080/v1                  lease http://<ai-box>:<port>/gpu/llm/<client>
<ai-box>         tts      http://<ai-box>:8000                     lease http://<ai-box>:<port>/gpu/tts/<client>
```

### The model gateway

`fleet controller` turns on the [model gateway](../ai/model-gateway.md): one OpenAI-compatible
URL, `https://model-gateway.<controller's domain>/v1`, for every host. Set it as `EXIST_MODEL_URL` (and leave
`EXIST_MODEL_KEY` blank) and opencode, pi and every automation reach whichever GPU box offers the
model they ask for, leasing it the way below.

### Leases

Each GPU box has room for one GPU service at a time, so anything that uses one leases it from
that box first. Every host shares one secret for this, `EXIST_FLEET_SECRET` in `.env.shared`,
which is also every model call's API key: the first run generates one, and `fleet join` puts the
controller's on every other host. Blank, nothing leases and the stack uses its own addresses.

With it set, the stack's decree scripts find each GPU service by asking the controller, every
time they need a new lease, and hold that host's lease while they use it:

- **`model_chat`, `pi_run` and OCR** take the lease of the service (`llm` or `strata`) whose
  offer lists the model `EXIST_MODEL_CHAT` (or `EXIST_MODEL_VISION`) names. A run of calls
  shares one lease, given back 5 seconds after the last call ends. A model address the run sets
  itself (`MODEL_URL`) takes none.
- **`comfy`** takes the `comfy` lease and holds it until ComfyUI's queue is empty, then 5 more
  seconds.
- A lease lasts 10 minutes and is renewed while it is held. One whose holder stops renewing
  frees the card soon after.

When no host offers it, they use this host's own: `EXIST_MODEL_URL`, and the local `comfyui`
container. Home Assistant, Open WebUI and code-server's opencode read `EXIST_MODEL_URL` too,
and take no lease.

By hand, `peers lease` asks for a lease and waits until it is held, then prints its id, and
`peers release` gives it back:

```bash
id=$(./existential.sh run peers lease <ai-box> comfy my-batch)
# ... use http://<ai-box>:8188 ...
./existential.sh run peers release <ai-box> comfy "$id"
```

### A decree project of your own

Any decree project, existential or not, can lease the fleet's GPUs through the `fleet_gpu` plugin,
the same lib the stack uses, which the controller's [model gateway](../ai/model-gateway.md) serves
at `https://model-gateway.<domain>` (built from the fleet lib it already leases through; it reads nothing of the host's).
Two lines in the project's `.decree/.env`:

```bash
EXIST_CONTROLLER=<the controller's domain>
EXIST_FLEET_SECRET=<secret>
```

Then, from the project's root, one command installs it (or updates it) and lists what the fleet
offers:

```bash
set -a; . .decree/.env; set +a; curl -fsSL -H "Authorization: Bearer $EXIST_FLEET_SECRET" "https://model-gateway.$EXIST_CONTROLLER/plugins/fleet_gpu.md" | decree install - && bash -c 'source .decree/machines/fleet_gpu/scripts/fleet.sh; fleet_offers | jq -c "{host, service, models}"'
```

and in its scripts, the same calls as the stack's:

```bash
source .decree/machines/fleet_gpu/scripts/fleet.sh
fleet_use llm || exit 1     # FLEET_URL: wherever llm is now, under its lease
curl -fsS "${FLEET_URL}/chat/completions" -d @request.json
fleet_done llm
```

`llm`, `strata`, `comfy` and `tts` all work this way; decree gives every script the two lines
from `.decree/.env`. The plugin file says the rest. It is written from the controller's checkout
at each `./existential.sh`, so to update it, run the command again.

### Moving a service to another host

What a box offers is `AI_BOX_SERVICES` in its `.decree/.env` (default `llm,comfy,tts`). To
move ComfyUI, take `comfy` out there and offer it on the other host. The box's next report,
within 5 minutes, leaves it out (`decree emit --machine reporting </dev/null` sends one now).
A lease held on the old host runs until it is given back, and the next lease is asked of the
new one, so no run is cut off and no caller's settings change.

An offer names a host by its `EXIST_TAILNET_NAME`, else its `EXIST_LOCAL_HOST_IP` (found by `./existential.sh`), else
its hostname. Nothing goes through the controller but the question: each host serves its own
traffic, and a host that stops reporting drops out of the list within 15 minutes. The peers
helper needs `jq` and `yq`.

## Things to know

- **Loki has no login of its own.** It listens only on the controller's loopback, and the other
  hosts reach it only through the gateway, which asks for the fleet secret. Never set
  `LOKI_BIND=0.0.0.0`: anyone on your network could then read every container's logs, and write
  offers that send other hosts' calls, and the fleet secret with them, to a host of theirs.
- **A GPU box's lease API is still plain HTTP**, on `:8801` with the fleet secret: a worker runs
  no Caddy. Between hosts on Tailscale, WireGuard encrypts it; on your own network, anyone who
  can watch its traffic can read the secret.
