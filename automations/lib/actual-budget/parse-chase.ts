#!/usr/bin/env tsx
// Parses a Chase transaction alert email into an actual-budget transaction.
//
// Reads from env vars (injected by decree from message frontmatter):
//   subject  — email subject line
//   date     — RFC 2822 date string
//
// Outputs JSON to stdout:
//   { amount: string, payee: string, date: string, notes: string }
//   or exits 0 with no output if the email is not a transaction alert.
//
// Chase subject patterns handled:
//   "Your $45.23 charge to STARBUCKS was authorized"
//   "A $12.00 charge to AMAZON.COM was authorized on your account"
//   "Transaction Alert - $23.50 at TARGET"

const subject = process.env.subject ?? '';
const rawDate = process.env.date ?? '';

if (!subject) {
    process.stderr.write('parse-chase: no subject in env\n');
    process.exit(1);
}

// ── Amount ────────────────────────────────────────────────────────────────────

const amountMatch = subject.match(/\$([\d,]+\.\d{2})/);
if (!amountMatch) {
    // Not a transaction alert — skip silently
    process.exit(0);
}
const amount = '-' + amountMatch[1].replace(/,/g, '');

// ── Payee ─────────────────────────────────────────────────────────────────────

let payee = '';
const chargeToMatch = subject.match(/charge to\s+(.+?)(?:\s+was\b|\s+on\b|$)/i);
const atMatch       = subject.match(/\bat\s+([A-Z0-9][^$\s][^.!?]*?)(?:\s+was\b|\s+on\b|$)/i);

if (chargeToMatch) {
    payee = chargeToMatch[1].trim();
} else if (atMatch) {
    payee = atMatch[1].trim();
} else {
    payee = subject;
}

// ── Date ──────────────────────────────────────────────────────────────────────

let txnDate: string;
try {
    txnDate = new Date(rawDate).toISOString().slice(0, 10);
} catch {
    txnDate = new Date().toISOString().slice(0, 10);
}

// ── Output ────────────────────────────────────────────────────────────────────

process.stdout.write(JSON.stringify({ amount, payee, date: txnDate, notes: subject }) + '\n');
