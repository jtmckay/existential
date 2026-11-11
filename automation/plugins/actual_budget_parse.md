---
machine: plugin
automation: actual_budget_parse
needs:
  - actual_budget
chart:
  description: Run a bank's parse script against one email and emit the transaction it finds to actual_budget.
  data:
    gmail_id: {type: string, default: ""}
    thread_id: {type: string, default: ""}
    from: {type: string, default: ""}
    to: {type: string, default: ""}
    subject: {type: string, default: ""}
    date: {type: string, default: ""}
    labels: {type: string, default: ""}
    has_attachments: {type: bool, default: false}
    # The tsx parser, e.g. /work/.decree/lib/actual-budget/parse-chase.ts.
    parse_script: {type: string, default: ""}
    account_id: {type: string, default: ""}
  initial: parse
  states:
    parse:
      invoke: actual_budget_parse
      transitions: {done: done}
      emits: [actual_budget]
    done: {final: true}
    failed: {final: true}
scripts:
  actual_budget_parse: |
    #!/usr/bin/env bash
    # actual_budget_parse
    #
    # Runs a parse script against one email from gmail_sync and emits actual_budget
    # when the script returns a transaction.
    #
    # The parse script reads the email's headers from its environment (subject,
    # date, from, to — exported below from this machine's params) and must output
    # a JSON object to stdout:
    #   { "amount": "-45.23", "payee": "STARBUCKS", "date": "2024-01-15", "notes": "..." }
    # Exit 0 with no output to skip (not a transaction). Exit non-zero on error.
    #
    # parse_script and account_id arrive through gmail_sync's GMAIL_FORWARD:
    #
    #   ---
    #   cron: "*/5 * * * *"
    #   machine: gmail_sync
    #   params:
    #     GMAIL_LABEL_FILTER: MyBank/Transactions
    #     GMAIL_ROUTINE: actual_budget_parse
    #     GMAIL_FORWARD: |
    #       parse_script=/work/.decree/lib/actual-budget/parse-chase.ts
    #       account_id=dedddddd-2222-4444-9999-111111cccccc
    #   ---

    set -euo pipefail

    TSX=/work/.decree/lib/node_modules/.bin/tsx
    [ -x "$TSX" ] || { echo "tsx not installed — run: ./existential.sh run actual-budget" >&2; exit 1; }

    parse_script="$DECREE_DATA_PARSE_SCRIPT"
    account_id="$DECREE_DATA_ACCOUNT_ID"

    [ -n "$parse_script" ] || { echo "Missing parse_script param."; exit 1; }
    [ -n "$account_id" ]   || { echo "Missing account_id param."; exit 1; }
    [ -f "$parse_script" ] || { echo "parse_script not found: ${parse_script}"; exit 1; }

    export subject="$DECREE_DATA_SUBJECT" date="$DECREE_DATA_DATE" \
           from="$DECREE_DATA_FROM" to="$DECREE_DATA_TO"

    # ── Run parser ────────────────────────────────────────────────────────────────

    result=$("$TSX" "$parse_script")

    # Empty output = not a transaction, skip cleanly
    if [ -z "$result" ]; then
        echo "Parser returned no output — not a transaction, skipping."
        exit 0
    fi

    # ── Extract fields ────────────────────────────────────────────────────────────

    amount=$(printf '%s' "$result" | jq -r '.amount // empty')
    payee=$(printf '%s'  "$result" | jq -r '.payee  // empty')
    txn_date=$(printf '%s' "$result" | jq -r '.date  // empty')
    notes=$(printf '%s'  "$result" | jq -r '.notes  // empty')

    if [ -z "$amount" ] || [ -z "$payee" ]; then
        echo "Parser output missing required fields (amount, payee): ${result}"
        exit 1
    fi

    [ -n "$txn_date" ] || txn_date=$(date +%Y-%m-%d)

    decree emit --machine actual_budget --param account_id="$account_id" \
        --param payee_name="$payee" --param date="$txn_date" --param notes="$notes" \
        >/dev/null <<<"$amount"

    echo "Queued transaction: ${amount} → ${payee} (${txn_date})"
lib:
  actual-budget/parse-chase.ts: |
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
    //   "You made a $47.66 transaction with AMAZON MKTPLACE PMTS"
    //   "Your $45.23 charge to STARBUCKS was authorized"
    //   "A $12.00 charge to AMAZON.COM was authorized on your account"

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

    // "You made a $47.66 transaction with AMAZON MKTPLACE PMTS"
    const transactionWithMatch = subject.match(/transaction with\s+(.+)$/i);
    // "Your $45.23 charge to STARBUCKS was authorized"
    const chargeToMatch = subject.match(/charge to\s+(.+?)(?:\s+was\b|\s+on\b|$)/i);

    if (transactionWithMatch) {
        payee = transactionWithMatch[1].trim();
    } else if (chargeToMatch) {
        payee = chargeToMatch[1].trim();
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
---
# actual_budget_parse

Run a bank's parse script against one email and emit the transaction it finds to actual_budget.
