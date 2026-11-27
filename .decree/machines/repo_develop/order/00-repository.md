---
machine: repo_develop
---
# The repository: one set of rules, a layout that says where things go, and gates that hold

## Overview

Existential is a curated homelab stack maintained by few people, so the repository has to
explain itself: every service looks like every other, every rule is written once, and every
rule that can be checked is. This is the ground every other order builds on.

## Outcome

- **`CLAUDE.md` holds the rules** and is kept current in the same change that alters one; the
  why and the edge cases live in `.claude/reference/<topic>.md` (volumes, templates,
  networking, testing, services, setup, models, decree, audience), each named in CLAUDE.md's
  "Read before you…" table. Its first principles: delete before adding; use what exists
  before building; match existing patterns.
- **Languages.** Code the repo owns is bash (preferred), TypeScript run with `tsx`, or Go for
  compiled services, never Python. Bash that runs on the host (`existential.sh`, what it
  sources, `exist.initial.sh`, the host plugin sync) runs on bash 3.2 and BSD tools, so a Mac
  works. Configuration is YAML; `.env` files hold only secrets and host-specific values.
- **Layout.** `src/` is host-run scripts: `src/lib/` utilities run by `./existential.sh run
  <name>`, `src/utils/` sourced only (`service-common.sh` is the one source of service
  discovery and enablement; `rendered-paths.sh` answers which template renders a path).
  `automation/` is scheduled, webhook and decree work. Service folders are
  `<category>/<slug>/` under `ai/`, `services/`, `nas/` and `hosting/`. A `.sh` is mode 644
  unless something executes it by path (`existential.sh`, `.githooks/*`, a decree script, an
  image entrypoint or hook), then 755.
- **Gates.** `.githooks/pre-commit` refuses secrets and rendered files; `.githooks/pre-push`
  runs the rest (lint, typecheck, unit suites, validators, the docs site build).
  `.github/workflows/ci.yml` runs the same gates on push and pull request; a gate is added to
  both. `repo_develop`'s gate is the pre-push hook.
- **Tests are read-only.** `./existential.sh test [name]` runs every suite or one; a test
  observes and never stacks state, and an unavoidable write is cleaned up in a verified
  `trap`. `./existential.sh validate [conventions|drift]` checks the conventions
  (`src/test/unit/validate-conventions.ts`) and template drift. A checkable claim in the docs
  gets a check.
- **The repo's own decree project** is its `.decree/`: `repo_develop` (decree's
  `decree_develop` with this repo's gate and conventions) and `repo_qa`, host plugins that are
  off until a person turns them on on the computer they develop from. Its order files, one per
  concern (infrastructure first, numbered; then one per feature), are the desired state of the
  repository; only `machines/repo_develop/order/`, `machines/repo_develop/state/order.git.txt`
  and `.gitignore` are tracked there.

## Constraints

- Nothing rendered, generated or secret is ever tracked.
- No rule is stated twice: CLAUDE.md states it, the reference explains it.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `.githooks/pre-push` runs
  **Then** it exits 0
- **Given** a rendered file or a credential staged
  **When** `git commit` runs
  **Then** the pre-commit hook refuses it
- **Given** `./existential.sh test host`
  **Then** it exits 0: what runs on the host runs on bash 3.2
