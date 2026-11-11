---
machine: plugin
automation: actual_budget
chart:
  description: Post one transaction to Actual Budget, the amount as the message body.
  data:
    account_id: {type: string, default: ""}
    payee_name: {type: string, default: ""}
    # YYYY-MM-DD; empty means today.
    date: {type: string, default: ""}
    notes: {type: string, default: ""}
    category_id: {type: string, default: ""}
  initial: post
  states:
    post:
      invoke: actual_budget
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  actual_budget: |
    #!/usr/bin/env bash
    # actual_budget
    #
    # Posts a transaction to Actual Budget using @actual-app/api. The details are
    # the params; the body is the amount in decimal dollars (negative = expense,
    # positive = income):
    #
    #   decree emit --machine actual_budget --param account_id=abc123-... \
    #       --param payee_name='Whole Foods' --param notes='Weekly groceries' <<<'-87.43'

    set -euo pipefail

    TSX=/work/.decree/lib/node_modules/.bin/tsx
    [ -f /secrets/actual-budget/credentials.env ] && [ -x "$TSX" ] \
        || { echo "Actual Budget is not set up — run: ./existential.sh run actual-budget" >&2; exit 1; }

    account_id="$DECREE_DATA_ACCOUNT_ID"
    payee_name="$DECREE_DATA_PAYEE_NAME"
    date="${DECREE_DATA_DATE:-$(date +%Y-%m-%d)}"
    notes="$DECREE_DATA_NOTES"
    category_id="$DECREE_DATA_CATEGORY_ID"

    [ -n "$account_id" ] || { echo "Missing account_id param."; exit 1; }
    [ -n "$payee_name" ] || { echo "Missing payee_name param."; exit 1; }

    # ── Extract amount from message body ─────────────────────────────────────────

    amount_raw=$(awk '
        NR==1 && /^---$/ { skip=1; next }
        skip && /^---$/  { skip=0; next }
        !skip
    ' "$DECREE_MESSAGE" | sed '/./,$!d' | head -1 | tr -d '[:space:]')

    [ -n "$amount_raw" ] || { echo "Missing amount in message body."; exit 1; }

    # ── Post transaction ──────────────────────────────────────────────────────────

    TXN_ACCOUNT_ID="$account_id" \
    TXN_PAYEE_NAME="$payee_name" \
    TXN_DATE="$date" \
    TXN_NOTES="$notes" \
    TXN_CATEGORY_ID="$category_id" \
    TXN_AMOUNT="$amount_raw" \
        "$TSX" "$DECREE_LIB/actual-budget/post-transaction.ts"

    echo "Posted ${amount_raw} → ${payee_name} (account: ${account_id})"
lib:
  actual-budget/post-transaction.ts: |
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
  actual-budget/setup.ts: |
    #!/usr/bin/env tsx
    // Interactive setup: connects to the Actual Budget server, lets the user select
    // a budget, verifies credentials, logs available accounts, and writes
    // credentials.env to SECRETS_DIR.
    //
    // Env vars (required):
    //   ACTUAL_URL       — server URL, e.g. http://actualBudget:5006
    //   ACTUAL_PASSWORD  — server password
    //   SECRETS_DIR      — directory to write credentials.env (default: /secrets/actual-budget)

    import path from 'node:path';
    import fs from 'node:fs';
    import readline from 'node:readline';
    import * as api from '@actual-app/api';

    interface Budget {
        cloudFileId: string;
        groupId: string;
        name: string;
    }

    interface Account {
        id: string;
        name: string;
        closed: boolean;
    }

    function requireEnv(key: string): string {
        const v = process.env[key];
        if (!v) { console.error(`Error: ${key} must be set.`); process.exit(1); }
        return v;
    }

    const SECRETS_DIR = process.env.SECRETS_DIR ?? '/secrets/actual-budget';
    const DATA_DIR    = path.join(SECRETS_DIR, 'data');
    const CREDENTIALS = path.join(SECRETS_DIR, 'credentials.env');

    const serverURL      = requireEnv('ACTUAL_URL');
    const serverPassword = requireEnv('ACTUAL_PASSWORD');

    function ask(question: string): Promise<string> {
        return new Promise(resolve => {
            const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
            rl.question(question, (answer: string) => { rl.close(); resolve(answer.trim()); });
        });
    }

    function askPassword(label: string): Promise<string> {
        return new Promise(resolve => {
            process.stdout.write(label);
            const stdin = process.stdin;
            try { stdin.setRawMode(true); } catch (_) {}
            stdin.resume();
            stdin.setEncoding('utf8');
            let pw = '';
            const onData = (key: string) => {
                if (key === '\r' || key === '\n') {
                    try { stdin.setRawMode(false); } catch (_) {}
                    stdin.pause();
                    stdin.removeListener('data', onData);
                    process.stdout.write('\n');
                    resolve(pw);
                } else if (key === '\u0003') {
                    process.exit(1);
                } else if (key === '\u007f') {
                    if (pw.length > 0) pw = pw.slice(0, -1);
                } else {
                    pw += key;
                }
            };
            stdin.on('data', onData);
        });
    }

    async function main(): Promise<void> {
        fs.mkdirSync(DATA_DIR, { recursive: true });

        console.log('  Connecting to ' + serverURL + '...');
        await api.init({ dataDir: DATA_DIR, serverURL, password: serverPassword });

        const budgets: Budget[] = await api.getBudgets();
        if (!budgets || budgets.length === 0) {
            console.error('  No budgets found on server.');
            await api.shutdown();
            process.exit(1);
        }

        console.log('\n  Available budgets:');
        budgets.forEach((b, i) => console.log(`    ${i + 1}. ${b.name}`));
        console.log('');

        const sel = await ask(`  Select budget [1-${budgets.length}]: `);
        const idx = parseInt(sel, 10) - 1;
        if (isNaN(idx) || idx < 0 || idx >= budgets.length) {
            console.error('  Invalid selection.');
            await api.shutdown();
            process.exit(1);
        }

        const budget = budgets[idx];
        console.log(`  Selected: ${budget.name}\n`);

        let budgetPassword = '';
        const hasPw = await ask('  Does this budget have an encryption password? (y/N): ');
        if (hasPw.toLowerCase() === 'y') {
            budgetPassword = await askPassword('  Budget password: ');
        }

        console.log('\n  Verifying credentials by downloading budget...');
        try {
            await api.downloadBudget(
                budget.groupId,
                budgetPassword ? { password: budgetPassword } : undefined
            );
            console.log('  Budget verified.');
        } catch (err) {
            console.error('  Failed: ' + (err as Error).message);
            await api.shutdown();
            process.exit(1);
        }

        const accounts: Account[] = await api.getAccounts();
        if (accounts && accounts.length > 0) {
            const col = Math.max(...accounts.map(a => a.name.length));
            console.log('\n  Accounts (use account_id in routine messages):');
            console.log('  ' + '─'.repeat(col + 40));
            for (const a of accounts) {
                const closed = a.closed ? '  [closed]' : '';
                console.log(`  ${a.name.padEnd(col)}  ${a.id}${closed}`);
            }
            console.log('');

            const accountsFile = path.join(SECRETS_DIR, 'accounts.json');
            fs.writeFileSync(accountsFile, JSON.stringify(accounts, null, 2) + '\n', { mode: 0o600 });
            console.log(`  Saved accounts to ${accountsFile}`);
        }

        await api.shutdown();

        const shellQuote = (s: string) => `'${s.replace(/'/g, "'\\''")}'`;
        const lines = [
            `ACTUAL_SERVER_URL=${shellQuote(serverURL)}`,
            `ACTUAL_SERVER_PASSWORD=${shellQuote(serverPassword)}`,
            `ACTUAL_BUDGET_ID=${shellQuote(budget.groupId)}`,
            `ACTUAL_BUDGET_NAME=${shellQuote(budget.name)}`,
            `ACTUAL_BUDGET_PASSWORD=${shellQuote(budgetPassword)}`,
        ].join('\n') + '\n';

        fs.writeFileSync(CREDENTIALS, lines, { mode: 0o600 });
        console.log(`\n  Saved: ${CREDENTIALS}`);
    }

    main().catch(err => { console.error('Error: ' + (err as Error).message); process.exit(1); });
---
# actual_budget

Post one transaction to Actual Budget, the amount as the message body.
