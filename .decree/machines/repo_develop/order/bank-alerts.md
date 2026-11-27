---
machine: repo_develop
---
# Bank alerts become budget entries

## Overview

Budgeting fails at data entry. A bank already emails each charge; those emails become Actual
Budget transactions, payee and amount filled in, minutes after the person pays.

## Outcome

- `gmail_sync` fetches new mail under one Gmail label (read-only access, granted once with
  `./existential.sh run automation gmail-sync`) and emits each message to its routine.
- `actual_budget_parse` runs a bank's parse script against one email and emits the
  transaction to `actual_budget`, which posts it. Chase is parsed out of the box; another bank
  is a small parser (Technical: *Actual Budget*, Another bank).
- `./existential.sh run actual-budget setup` picks the budget and accounts;
  `./existential.sh run automation gmail-transactions-cron` offers the label → account schedule
  in `workspace/ai/proposed/`, which the person moves to turn on.
- `gmail` files one whole email in the emails directory, for routines that want the mail itself.
- Guide: *Money, Photos and the House*, Bank alerts; Technical: *Actual Budget*, *Gmail*.

## Constraints

- What only the person can do is listed in order: the bank's alert for every transaction, a
  Gmail label per bank, then the three commands.
- Credentials live in `/secrets`, never the workspace.

## Acceptance Criteria

- **Given** `./existential.sh test decree`
  **Then** each of the four checks alone with only its `needs:`
- **Given** `./existential.sh validate conventions`
  **Then** it passes
