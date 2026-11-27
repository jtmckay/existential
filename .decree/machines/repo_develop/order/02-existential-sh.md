---
machine: repo_develop
---
# existential.sh: one command, one path per action, and a stack that comes back after a reboot

## Overview

Everything a person does to the stack goes through one script. It must be safe to run any
number of times, never need sudo, and leave the stack starting with the computer.

## Outcome

- **The bare run** renders every enabled service, runs each `exist.initial.sh`, generates the
  compose file and `.env`, installs each decree project's plugins at this checkout's version,
  and pulls and builds every enabled image (the decree image when its build context changed)
  without touching running containers. `git pull && ./existential.sh` is the upgrade.
- **Actions**, each with one path: `service [list|on|off]` (a picker, or by name; sets the
  flag and rebuilds through the same sequence as the bare run), `plugin
  [list|on|off|sync|export]`, `run` (lists every action; `run <utility>` is `src/lib/`,
  `run <slug> [action]` a service's `exist.<action>.sh`), `test [name]` (a unit or
  integration suite by file name, else a service's `exist.test.sh`; no suite list kept by
  hand), `validate [name]`, `e2e [down]`, and `reset` (archives every rendered file to
  `archive/<timestamp>/`, asks first, never touches volumes; not a `run` utility). Unknown
  flags are unknown actions; `--help`, `-h` and `help` print the usage, which lists exactly
  these.
- **Tools run in a container.** yq, tsx and decree run in `existential-adhoc`, built on first
  use, so the host needs only Docker or Podman. A host with neither is a worker, set up with
  the host's own decree and yq.
- **Never under sudo.** Run through sudo (effective uid 0 with `SUDO_USER` set) it exits 1
  before writing anything, printing the two fixes: add `$SUDO_USER` to the docker group (then
  log out and in, not `newgrp`) and `./existential.sh run fix-permissions` to reclaim what a
  sudo run left root-owned. Plain root with no `SUDO_USER` is allowed. It runs sudo only when
  a person says yes (below); anything else that needs root (the docker group, a system unit,
  Tailscale's operator) is printed as the next step.
- **An answer is never asked twice.** Every question's answer is kept the moment it is given
  (`.env.shared`, or `.env.role` for the first question until `.env.shared` exists), before
  anything that can still fail, so a run that stops goes on from there next time.
- **What it lacks, it offers to install.** A tool a step needs and the host lacks (curl, tmux,
  unzip through the package manager; decree, yq and alloy into `~/.local/bin` at the versions
  the stack pins) is offered in one go with the commands shown, and Enter runs them (a package
  manager's through sudo, which asks its own password), so setup goes on with Enter after
  Enter. Without a terminal, or on `n`, nothing runs and each command is printed instead.
- **The host's decree daemon is installed, not just started.** `./existential.sh run
  host-daemon install` starts it now and at every boot: a systemd user unit
  (`existential-host.service`, the checkout's folder and the `PATH` its tools are on, enabled,
  with linger on, asking before `sudo loginctl enable-linger` where that takes root), or a
  LaunchAgent on a Mac; the daemon is the `existential-host` tmux session, never started twice.
  `status` says whether it runs, starts at boot and has linger, and the last report;
  `uninstall` removes what starts it at boot. Every run with a host plugin on offers the install
  with Enter while no daemon runs, and warns when one runs that nothing would bring back after a
  reboot. A worker's run ends with where it stands: controller, alloy, daemon, boot, last
  report.
- **The stack starts with the computer.** Every service is `restart: unless-stopped`, and each
  run leaves the engine able to bring it back: for rootless Podman it enables the user's
  `podman-restart.service` and linger without sudo (printing the command for what it could
  not do); for Docker with systemd it prints `sudo systemctl enable docker` when that unit is
  off and nothing when it is on; for rootful Podman the same for `podman-restart.service`;
  Docker Desktop and hosts without systemd need nothing checked, and Getting Started names
  Docker Desktop's "start when you sign in". A failure here never stops the run.

## Constraints

- An `.env.shared` holding a key the repo no longer uses keeps working: the key is ignored.
- Rendered files are never re-rendered; a removal is applied to a rendered copy by hand or by
  the run that removes it, never by re-rendering.

## Acceptance Criteria

- **Given** effective uid 0 and `SUDO_USER=someone`
  **When** `existential.sh --help` runs
  **Then** it exits 1 and its output contains `usermod -aG docker`
- **Given** rootless Podman with neither setting on
  **When** `./existential.sh` runs
  **Then** `systemctl --user enable podman-restart.service` and `loginctl enable-linger <user>`
  have been called
- **Given** a first run whose step fails on a missing tool after its questions were answered
  **When** `./existential.sh` runs again
  **Then** none of those questions is asked again
- **Given** a worker missing tmux, with a terminal
  **When** `./existential.sh` runs
  **Then** it shows the command that installs tmux and runs it on Enter
- **Given** a Linux worker with systemd and no daemon, with a terminal
  **When** `./existential.sh` runs and the offer is taken with Enter
  **Then** `systemctl --user is-enabled existential-host` says enabled and `tmux has-session -t
  =existential-host` succeeds
- **Given** Docker whose `docker.service` is enabled
  **When** `./existential.sh` runs
  **Then** it prints nothing about boot
- **Given** `./existential.sh run`
  **Then** `reset` is not among the utilities
