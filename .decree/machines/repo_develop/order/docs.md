---
machine: repo_develop
---
# The docs describe the repo as it is: a Guide for the person, Technical docs for how it is built

## Overview

The site led with what the stack is, then turned straight into how it is assembled
(configuration, compose merging, nip.io) and kept what it does for a person inside the install
guide and a table of shell commands. The same Tailscale, domain and plugin explanations were
written three or four times, per-flow pages restated settings the machines declare (and had
drifted from them), and forty pages documented tools the stack does not run.

## Outcome

- **The docs describe the repository as it is.** `README.md`, `site/docs/` and the homepage
  (`site/src/`) change in the same change that makes them untrue; diagrams show the current
  architecture; prose that is still true keeps its voice. A statement a script can check is
  checked (`validate conventions`, a unit test): what Core installs, one page per service
  (`service: <cat>/<slug>` frontmatter), every `plugin on`/`service on` line naming something
  real, every relative link naming its `.md` file.
- **Two sidebars** (`site/sidebars.ts`), *Guide* and *Technical* in the navbar.
- **The Guide** is for the person in `.claude/reference/audience.md`: `intro`, `getting-started`
  (install only), `flows/` (What It Does: one page per problem, each section the problem, what
  happens, the `service on`/`plugin on` lines, and what is left for the person), `workspace`
  and `faq`. It explains nothing about how the stack is built.
- **Technical** is everything else: `how-it-works` (How It's Built), `configuration`,
  `networking` (the one home for Tailscale, Caddy names, an owned domain and VPNs), `plugins/`
  (the plugin system, the file handler and processor mechanisms, routing, and Note → Action as
  the worked example), `hosting/`, the per-service reference, `backlog/`, Alternatives and the
  licensing pages.
- **A plugin's settings are its machine's `data:`**, in its plugin file; no docs page restates
  them in a table.
- **A retired tool is a row** in `graveyard/index.md`, with a one-line reason; there are no
  per-tool graveyard pages.
- **`backlog/`** holds notes on things not built yet (HAwake, AutoVoice); nothing there ships.
- The homepage pitch is owned by `audience.md`; nothing here contradicts it.

## Constraints

- No page is in both sidebars; a Guide page links to Technical for the mechanism, never
  repeats it.
- Every relative link names its `.md` file and every anchor resolves (the site build).

## Acceptance Criteria

- **Given** `./existential.sh validate conventions`
  **Then** it exits 0: every plugin a person turns on has its `plugin on` line on some docs page,
  and every such line names a real plugin or service
- **Given** the site build (`npm run build` in `site/`)
  **Then** it succeeds with no broken links
- **Given** `site/docs/`
  **When** it is searched for a settings table of a plugin's cron params, a per-tool graveyard
  page, or a Tailscale or owned-domain walkthrough outside `networking.md`
  **Then** there is none
