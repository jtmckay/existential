// Splits an existing Actual Budget transaction into subtransactions.
//
// Required env vars:
//   TXN_TRANSACTION_ID  — ID of the parent transaction to split
//   TXN_SPLITS_JSON     — JSON array: [{"name": "Item", "amount_cents": -450}, ...]
//                         Amounts must be in integer cents and must sum to the parent amount.
//
// Actual Budget credentials loaded from /secrets/actual-budget/credentials.env

import * as api from "@actual-app/api";
import * as dotenv from "dotenv";

dotenv.config({ path: "/secrets/actual-budget/credentials.env" });

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) { console.error(`Error: ${key} must be set.`); process.exit(1); }
  return v;
}

interface SplitItem {
  name: string;
  amount_cents: number;
}

const DATA_DIR       = "/secrets/actual-budget/data";
const serverURL      = requireEnv("ACTUAL_SERVER_URL");
const serverPassword = requireEnv("ACTUAL_SERVER_PASSWORD");
const budgetId       = requireEnv("ACTUAL_BUDGET_ID");
const budgetPassword = process.env.ACTUAL_BUDGET_PASSWORD ?? "";

const transactionId = requireEnv("TXN_TRANSACTION_ID");
const splitsJson    = requireEnv("TXN_SPLITS_JSON");

let splits: SplitItem[];
try {
  splits = JSON.parse(splitsJson);
} catch {
  console.error("TXN_SPLITS_JSON is not valid JSON");
  process.exit(1);
}

async function main(): Promise<void> {
  await api.init({ dataDir: DATA_DIR, serverURL, password: serverPassword });
  await api.downloadBudget(budgetId, budgetPassword ? { password: budgetPassword } : undefined);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (api.updateTransaction as any)(transactionId, {
    subtransactions: splits.map((s) => ({ amount: s.amount_cents, notes: s.name })),
  });

  console.log(`Split transaction ${transactionId} into ${splits.length} items.`);
  await api.shutdown();
}

main().catch((err: Error) => {
  console.error("Error: " + err.message);
  process.exit(1);
});
