---
sidebar_position: 1
---

# Actual Budget

Connects Decree to your Actual Budget server, enabling automated transaction imports from bank alert emails. Once configured, the `actual-budget` and `actual-budget-parse` routines are enabled automatically and credentials are loaded by the container at runtime.

New to Actual Budget? Start with the [service setup](../services/actual-budget) first.

## Prerequisites

Your Actual Budget server must be running and reachable from the Decree container. If you're using the full Existential stack, it's at `http://actual-budget:5006`.

## Setup

```bash
./existential.sh setup actual-budget
```

The script will:

1. Prompt for your server URL and password
2. Connect and list available budgets
3. Let you select a budget and optionally enter its encryption password
4. Verify credentials by downloading the budget
5. Display all accounts with their IDs
6. Save credentials to `services/decree/secrets/actual-budget/credentials.env`
7. Save the account list to `services/decree/secrets/actual-budget/accounts.json`
8. Enable the `actual-budget` and `actual-budget-parse` routines in `automations/config.yml`

## Account IDs

After setup, account IDs are printed to the terminal and saved to `accounts.json`. You'll need an account ID when configuring any automation that imports transactions — it tells Decree which account to post to.

If you add accounts later, re-run `./existential.sh setup actual-budget` to refresh credentials and the account list.

## Next Steps

Set up automated transaction imports from bank alert emails: [Bank Alert → Gmail → Actual Budget](../decree/transaction-gmail-actual-budget)
