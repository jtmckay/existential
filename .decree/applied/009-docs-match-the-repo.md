---
machine: develop
---
# The documentation describes the repository as it is

## Overview

The docs are how a new user decides whether to install this and how to use it. When they
describe a stack that no longer exists, they cost more than having no docs. Several
recent changes (Core's membership, the workspace's decree project, models reached through an
OpenAI-compatible URL, hermes being optional, agents in code-server) changed what is true.

## Outcome

- `README.md`, `site/docs/` and the homepage (`site/src/`) describe what the repository
  actually does now: what Core installs, where the user works (`workspace/` with `notes/`
  and `.decree/`), how automations are written and run, how models are reached, and which
  services are optional add-ons.
- Diagrams show the current architecture. No diagram puts a service at the centre that Core
  doesn't install.
- Every service the docs link to exists in the repo (outside `graveyard/`), and every service
  folder outside `graveyard/` has a docs page.
- Statements a script can check stay checked. Where a doc names a count, a file, a key or
  a command, `./existential.sh validate` (or a unit test) fails when it stops being true, as
  it already does for README's and intro's "What Core installs".

## Constraints

- Prose that is still true stays as it is. Change what is wrong, not the voice.
- The homepage pitch is owned by `008-value-proposition.md`. Don't contradict it.

## Acceptance Criteria

- **Given** the docs site build
  **When** it runs
  **Then** it succeeds with no broken links
- **Given** the services `.env.exist.shared` ships on
  **When** it is compared with what `README.md` and `site/docs/intro.md` say Core installs
  **Then** they agree
- **Given** a docs link to a service page, or a service folder
  **When** `./existential.sh validate` runs
  **Then** a link to a missing service or a service with no page fails it
