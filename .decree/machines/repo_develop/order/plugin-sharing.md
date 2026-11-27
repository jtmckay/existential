---
machine: repo_develop
---
# Sharing machines between stacks, accepted by a person

## Overview

Two people running the stack should be able to trade what they built, without either one
running the other's code by accident.

## Outcome

- `plugin_share`: another stack asks for one machine (`POST /plugins/<machine>/share/<client>`)
  and is sent it as a plugin file, at once if listed in `PLUGIN_SHARE_ALLOW`, otherwise once the
  person says yes on their phone; asked for none, it sends the list, each marked free or asks.
- `plugin_request`: ask another stack for its list or one machine (`PLUGIN_SHARE_NAME`,
  `PLUGIN_PEER_<FROM>` and its token in `automation/.env`).
- `plugin_offer`: what comes back. A list goes to the phone; a plugin waits in
  `workspace/ai/proposed/` until the person moves it into `.decree/plugins/` and installs it.
- Needs automation-webhook. Technical: *Plugins*, Sharing.

## Constraints

- Nothing is installed anywhere without a person accepting it; the docs say to read its
  scripts first, since they run with this stack's access.

## Acceptance Criteria

- **Given** `./existential.sh test plugins`
  **Then** it exits 0
