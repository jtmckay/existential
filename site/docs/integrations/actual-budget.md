---
sidebar_position: 1
---

# Actual Budget

Lets the `actual_budget` and `actual_budget_parse` machines post transactions to your Actual Budget server.

New to Actual Budget? Start with the [service setup](../services/actual-budget.md) first.

## Prerequisites

Your Actual Budget server must be running and reachable from the Decree container. If you're using the full Existential stack, it's at `http://actual-budget:5006`.

## Setup

```bash
./existential.sh run actual-budget setup
```

The script will:

1. Prompt for your server URL and password
2. Connect and list available budgets
3. Let you select a budget and optionally enter its encryption password
4. Verify credentials by downloading the budget
5. Display all accounts with their IDs
6. Save credentials to `automation/secrets/actual-budget/credentials.env`
7. Save the account list to `automation/secrets/actual-budget/accounts.json`
8. Point you at `./existential.sh run automation gmail-transactions-cron`, which wires a Gmail label to an account

## Account IDs

After setup, account IDs are printed to the terminal and saved to `accounts.json`. You'll need an account ID when configuring any automation that imports transactions — it tells Decree which account to post to.

If you add accounts later, re-run `./existential.sh run actual-budget setup` to refresh credentials and the account list.

## Another bank

Each bank alert is read by a parse script: `workspace/.decree/lib/actual-budget/parse-<bank>.ts`.
Chase's ships. A parser reads the email's `subject`, `date`, `from` and `to` from its environment
and prints one JSON object:

```json
{ "amount": "-42.00", "payee": "Whole Foods", "date": "2026-04-21", "notes": "..." }
```

Copy `parse-chase.ts` for your bank, then run `./existential.sh run automation
gmail-transactions-cron` again: it lists the new script.

To try one without waiting for mail:

```bash
echo | docker exec -i automation decree emit --machine actual_budget_parse \
  --param subject='You made a $42.00 transaction with WHOLE FOODS' \
  --param date='Mon, 21 Apr 2026 12:00:00 +0000 (UTC)' \
  --param parse_script=/work/.decree/lib/actual-budget/parse-chase.ts \
  --param account_id=<your-account-id>
```

The whole flow, from the bank's side: [Money, Photos and the House](../flows/home.md#bank-alerts-become-budget-entries).
