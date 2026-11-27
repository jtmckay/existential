---
machine: repo_develop
---
# Core is "open the work dir, talk to an AI, have decree automate it"; the first run asks what this computer is

## Overview

Core is what a new install is, and nothing more: a person opens the work dir, starts a
conversation with an AI agent, and has decree automate things for them. Everything else is an
add-on, because most installs run files, DNS, the house and GPU models on other servers, and
every service in Core is one more thing to understand. Every question before the stack is up
is a chance to stall, and for this audience a stall on day one is often the end.

## Outcome

- **Core is what `.env.exist.shared` ships on, exactly:** code-server, automation (the decree
  daemon), ntfy, qmd (search) and Firecrawl (the web). No GPU and no reverse proxy: Tailscale
  on the host, when it is there, gives Core HTTPS (see `networking.md`).
- **Everything past Core is an add-on**: a service turned on with `./existential.sh service
  on`, or a plugin with `plugin on`, its manual steps on its Guide page or service page.
  automation-webhook is an add-on with its own flag; everything it triggers can also be
  started from code-server's terminal. Backups are outside Core; Getting Started suggests
  putting the workspace under git with a remote the person chooses, or turning backups on.
- **The default plugins need nothing beyond Core's services.**
- **The first run asks one question: what is this computer?**
  - **a) Core** (the default, Enter): Core and nothing more; then the login, asked the moment
    `.env.shared` is made and before any service renders it: a username (Enter keeps `admin`)
    and a password (Enter generates one; a typed one is asked twice, unseen, at least 8 of
    `A-Za-z0-9._-`), kept as `EXIST_USERNAME`/`EXIST_PASSWORD`. **No controller**: Loki,
    Grafana and the model gateway are not Core, and setup never turns them on; a person makes
    a host the controller later with `./existential.sh run fleet controller`. **Nothing is set
    up on the host itself**: no systemd unit, no host daemon, no `report_host`.
  - **b) A worker**: it asks for the controller's address and reports this host to it, with
    `report_host` and nothing else: no services, nothing in containers.
  - A host with no docker or podman is not asked: it can only be a worker.
  - With no terminal nothing is asked: Core as it ships, `admin` and a generated password.
  - The answer is `EXIST_HOST_ROLE` (`core` or `worker`), kept the moment it is given. An install from before the question is
    recorded as what it already is, and not asked.
  The run prints the login once at its end with where it is stored, and where Core is. One
  step is left: the model (`EXIST_MODEL_URL`, `EXIST_MODEL_KEY`).
- **Only an email is asked**, when an enabled service first uses one (Nextcloud, Home
  Assistant and the other add-ons that create an account), and never again.
- **Everything that states what Core contains agrees with `.env.exist.shared`**: README's and
  intro's "What Core installs", the tour's "With Core" flows (each on Core's services, plus a
  chat model where it says so), and `./existential.sh run footprint core`. After
  `docker compose up -d`, Getting Started sends the person to code-server.

## Constraints

- An existing install's values are kept; the env-file contract holds.

## Acceptance Criteria

- **Given** the `EXIST_IS_*=true` lines in `.env.exist.shared`
  **Then** they are exactly code-server, automation, ntfy, qmd and Firecrawl, and
  `validate conventions` passes (README and intro list the same)
- **Given** a fresh checkout
  **When** `./existential.sh` runs for the first time with no terminal
  **Then** it asks nothing, builds Core, and its output names the username and password and
  where they are kept
- **Given** a first run that answers a, then Enter twice
  **Then** `EXIST_USERNAME=admin`, the generated password is kept, Loki, Grafana and the model
  gateway are off, `.decree/plugins/.on` does not name `report_host`, and no
  `existential-host.service` was written
- **Given** a first run that answers b and a controller's domain
  **Then** every `EXIST_IS_*` is false, `EXIST_CONTROLLER` is that domain, and `report_host`
  is on
- **Given** an install that then enables an add-on needing an email
  **When** `./existential.sh` runs
  **Then** it asks for the email once, and never again
