---
machine: develop
---
# existential.sh refuses to run under sudo

## Overview

On a host where the user is not in the `docker` group, running `sudo ./existential.sh`
renders every file root-owned at mode 600 and records `EXIST_PUID=0`, so the user can't read
their own Caddyfile or `.env` files and every container runs as root.

## Outcome

- `./existential.sh` invoked through sudo (effective uid 0 with `SUDO_USER` set) exits 1
  before it writes anything. It prints why, and it prints the two commands that fix it:
  adding `$SUDO_USER` to the docker group (then logging out and back in), and
  `./existential.sh run fix-permissions` to reclaim what an earlier sudo run left root-owned.
- Running as plain root with no `SUDO_USER` behaves as before.
- The getting-started prerequisites say Docker must work without sudo.

## Constraints

- The hint does not depend on `newgrp` (on some Ubuntu releases it needs an extra package).

## Acceptance Criteria

- **Given** effective uid 0 and `SUDO_USER=someone`
  **When** `existential.sh --help` runs
  **Then** it exits 1 and its output contains `usermod -aG docker`
- **Given** a normal user
  **When** `existential.sh --help` runs
  **Then** it exits 0
