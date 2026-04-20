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

    const lines = [
        `ACTUAL_SERVER_URL=${serverURL}`,
        `ACTUAL_SERVER_PASSWORD=${serverPassword}`,
        `ACTUAL_BUDGET_ID=${budget.groupId}`,
        `ACTUAL_BUDGET_NAME=${budget.name}`,
        `ACTUAL_BUDGET_PASSWORD=${budgetPassword}`,
    ].join('\n') + '\n';

    fs.writeFileSync(CREDENTIALS, lines, { mode: 0o600 });
    console.log(`\n  Saved: ${CREDENTIALS}`);
}

main().catch(err => { console.error('Error: ' + (err as Error).message); process.exit(1); });
