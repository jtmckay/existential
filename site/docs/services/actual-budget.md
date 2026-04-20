---
sidebar_position: 1
---

# Actual Budget

- Source: https://github.com/actualbudget/actual
- License: [MIT](https://github.com/actualbudget/actual/blob/master/LICENSE)
- Alternatives: YNAB, Mint, PocketSmith, Firefly III, GnuCash

[Actual Budget](https://actualbudget.org/) is a local-first personal finance manager. Your data lives on your own server — no third-party cloud. It uses envelope-style zero-based budgeting: every dollar gets assigned a job before you spend it.

:::tip Official docs
Actual Budget's own documentation is thorough. For anything not covered here — reports, goals, rules, bank sync — start at [actualbudget.org/docs](https://actualbudget.org/docs/).
:::

## Features

- **Local-First Budgeting**: Complete control of your financial data with local storage
- **Zero-Based Budgeting**: Assign every dollar a purpose using envelope-style budgeting
- **Bank Synchronization**: Import transactions from banks and financial institutions
- **Cross-Platform**: Web-based interface accessible from any device
- **Open Source**: Fully open-source personal finance management
- **Real-time Sync**: Multi-device synchronization with end-to-end encryption
- **Budget Templates**: Create and reuse budget templates for consistent planning
- **Goal Tracking**: Set and monitor savings goals and debt payoff plans
- **Reports & Analytics**: Spending trends, net worth tracking, and custom reports
- **Mobile Support**: Responsive web interface optimized for mobile devices

## First-Time Setup

### 1. Create a budget file

On first load you'll be prompted to create a new budget or import one. Choose **Create new file** and give it a name.

A budget file is the container for all your accounts, categories, and transactions. You can have more than one (e.g. personal and business), but for most people one is enough.

### 2. Add accounts

Accounts represent your real-world financial accounts — checking, savings, credit cards, investments. Go to **Add account** in the left sidebar.

Actual distinguishes between:

- **On-budget accounts** — spending money you track and budget. Checking, savings, and credit cards go here.
- **Off-budget accounts** — assets you want to track (investments, property) but don't budget from.

Add at least one on-budget account for each card or bank account you want to track.

### 3. Set up your budget

With accounts created, assign your available money to budget categories. Actual walks you through this on first load — use the [official guide](https://actualbudget.org/docs/getting-started/envelope-budgeting/) if you want a deeper explanation of how envelope budgeting works.

## Integrations

Connect Actual Budget to Decree to import transactions automatically from bank alert emails: [Actual Budget integration](../integrations/actual-budget)
