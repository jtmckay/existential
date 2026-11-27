---
machine: repo_develop
---
# Photos, the house and office documents, set up without the setup screens

## Overview

Each of these services has a first-run wizard that stands between "turned on" and "working".
An order file does it once the service answers, so turning one on is one line.

## Outcome

- `immich_setup` makes Immich's admin from `EXIST_EMAIL` and `EXIST_PASSWORD` and adds the NAS
  photos as a read-only External Library.
- `homeassistant_onboarding` finishes Home Assistant's onboarding with an admin from
  `EXIST_USERNAME`; `homeassistant_voice` wires Wyoming speech-to-text and text-to-speech, and
  the chat model as the conversation agent, into the Assist pipeline.
- `nextcloud_richdocuments` installs richdocuments and points it at Collabora, with the WOPI
  allowlist set to the exist bridge.
- Each is an order, waiting on its service in a first `wait_for_<service>` state.
- Guide: *Money, Photos and the House*.

## Constraints

- Run once; editing the order runs it again. Nothing here overwrites what the person changed in
  the app afterwards.

## Acceptance Criteria

- **Given** `./existential.sh test decree`
  **Then** each checks alone with only its `needs:`
- **Given** `./existential.sh validate conventions`
  **Then** it passes
