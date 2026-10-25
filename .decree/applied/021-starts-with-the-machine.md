---
machine: develop
---
# Once it has run, the stack starts with the machine until you stop it

## Overview

Every trigger the stack has (cron, the webhook, file changes, the inbox) runs inside its
containers, so "it keeps working" comes down to the containers coming back after a reboot.
Each one is `restart: unless-stopped`, which only helps if the container engine itself starts
at boot. Docker from its packages does; rootless Podman does not, until two per-user settings
are on; Docker Desktop does only once it is running.

## Outcome

- Every service in every template has `restart: unless-stopped`.
- `./existential.sh` (and `flow`) leaves the engine set to bring the stack back at boot:
  - rootless Podman: it enables the user's `podman-restart.service` and turns on linger for
    the user, both without sudo, and prints the one command for whichever it could not do;
  - Docker with systemd: when `docker.service` is not enabled, it prints
    `sudo systemctl enable docker`, and stays silent when it is;
  - rootful Podman: the same for `podman-restart.service`;
  - Docker Desktop, or a host without systemd: nothing to check; the docs name Docker
    Desktop's own "start when you sign in" setting.
- `site/docs/getting-started.md`'s prerequisites say the stack starts with the machine once
  it has run, and what that needs per engine.

## Constraints

- `existential.sh` never runs sudo and never enables a system unit itself.
- A failure here never stops the run.

## Acceptance Criteria

- **Given** rootless Podman with neither setting on
  **When** `./existential.sh` runs
  **Then** `systemctl --user enable podman-restart.service` and `loginctl enable-linger <user>`
  have been called
- **Given** Docker whose `docker.service` is not enabled
  **When** `./existential.sh` runs
  **Then** it prints `sudo systemctl enable docker` and enables nothing itself
- **Given** Docker whose `docker.service` is enabled
  **When** `./existential.sh` runs
  **Then** it prints nothing about boot
