// Reverts a split transaction back to a single transaction by clearing subtransactions.
//
// Required env vars:
//   TXN_TRANSACTION_ID  — ID of the parent transaction whose split should be cleared
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

const DATA_DIR       = "/secrets/actual-budget/data";
const serverURL      = requireEnv("ACTUAL_SERVER_URL");
const serverPassword = requireEnv("ACTUAL_SERVER_PASSWORD");
const budgetId       = requireEnv("ACTUAL_BUDGET_ID");
const budgetPassword = process.env.ACTUAL_BUDGET_PASSWORD ?? "";

const transactionId = requireEnv("TXN_TRANSACTION_ID");

async function main(): Promise<void> {
  await api.init({ dataDir: DATA_DIR, serverURL, password: serverPassword });
  await api.downloadBudget(budgetId, budgetPassword ? { password: budgetPassword } : undefined);

  await api.updateTransaction(transactionId, { subtransactions: [] });

  console.log(`Reverted split on transaction ${transactionId}.`);
  await api.shutdown();
}

main().catch((err: Error) => {
  console.error("Error: " + err.message);
  process.exit(1);
});
