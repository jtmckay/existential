#!/usr/bin/env tsx
// Posts a single transaction to Actual Budget.
//
// Env vars (required):
//   ACTUAL_SERVER_URL       — server URL
//   ACTUAL_SERVER_PASSWORD  — server password
//   ACTUAL_BUDGET_ID        — budget sync ID
//   ACTUAL_BUDGET_PASSWORD  — budget encryption password (may be empty)
//   TXN_ACCOUNT_ID          — Actual Budget account UUID
//   TXN_PAYEE_NAME          — payee name string
//   TXN_DATE                — YYYY-MM-DD
//   TXN_AMOUNT              — decimal dollars (negative = expense, positive = income)
//
// Optional env vars:
//   TXN_NOTES               — memo/notes string
//   TXN_CATEGORY_ID         — Actual Budget category UUID

import * as api from '@actual-app/api';
import * as dotenv from "dotenv";

// ── Load credentials ──────────────────────────────────────────────────────────
dotenv.config({
  path: "/secrets/actual-budget/credentials.env",
});

function requireEnv(key: string): string {
    const v = process.env[key];
    if (!v) { console.error(`Error: ${key} must be set.`); process.exit(1); }
    return v;
}

interface Transaction {
    date: string;
    amount: number;
    payee_name: string;
    notes: string;
    category?: string;
}

const DATA_DIR       = '/secrets/actual-budget/data';
const serverURL      = requireEnv('ACTUAL_SERVER_URL');
const serverPassword = requireEnv('ACTUAL_SERVER_PASSWORD');
const budgetId       = requireEnv('ACTUAL_BUDGET_ID');
const budgetPassword = process.env.ACTUAL_BUDGET_PASSWORD ?? '';

const accountId  = requireEnv('TXN_ACCOUNT_ID');
const payeeName  = requireEnv('TXN_PAYEE_NAME');
const date       = requireEnv('TXN_DATE');
const notes      = process.env.TXN_NOTES ?? '';
const categoryId = process.env.TXN_CATEGORY_ID ?? null;
const amountRaw  = requireEnv('TXN_AMOUNT');

// Actual Budget stores amounts as integer cents ($1.00 = 100)
const amount = Math.round(parseFloat(amountRaw) * 100);
if (isNaN(amount)) { console.error('Invalid amount: ' + amountRaw); process.exit(1); }

async function main(): Promise<void> {
    await api.init({ dataDir: DATA_DIR, serverURL, password: serverPassword });

    await api.downloadBudget(budgetId, budgetPassword ? { password: budgetPassword } : undefined);

    const txn: Transaction = { date, amount, payee_name: payeeName, notes };
    if (categoryId) txn.category = categoryId;

    const ids: string[] = await api.addTransactions(accountId, [txn]);
    console.log('Transaction added (id: ' + (ids[0] ?? 'unknown') + ')');

    await api.shutdown();
}

main().catch(err => { console.error('Error: ' + (err as Error).message); process.exit(1); });
