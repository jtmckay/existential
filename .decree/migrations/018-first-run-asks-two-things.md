---
machine: develop
---
# A Core first run asks two things: a username and a password

## Overview

Core is code-server, decree, ntfy and Tailscale. Only ntfy needs an account name (its phone app
logs in with one), and nothing in Core needs an email. Every question before the stack is up
is a chance to stall, and for this audience a stall on day one is often the end. But a login
nobody told you about is worse than one more question.

## Outcome

- A first run of `./existential.sh` with only Core enabled asks for a username and a password,
  and nothing else about the user: no email.
- Both questions offer a default you can accept with Enter: the username a sensible default,
  the password generated.
- When the user accepts a default, the end of that first run says what it is and where to find
  it again (the key and file it lives in), next to how to log in to ntfy's phone app.
- `EXIST_EMAIL` is asked for only when an enabled service needs it (Nextcloud, Home Assistant
  and the other add-ons that create an account), the first time one is enabled.
- An existing install's values are kept.

## Constraints

- The env-file contract holds: a rendered `.env*` is never overwritten, and new keys are
  appended.
- The password itself is never printed; the run says where it is stored.

## Acceptance Criteria

- **Given** a fresh checkout with only Core enabled
  **When** `./existential.sh` runs for the first time
  **Then** it asks for a username and a password, and not for an email
- **Given** a first run where both defaults are accepted
  **When** it finishes
  **Then** its output names the username and where both are stored, and doesn't contain the
  password
- **Given** an install that then enables an add-on needing an email
  **When** `./existential.sh` runs
  **Then** it asks for the email once, and never again
