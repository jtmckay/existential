---
name: Bank alerts become budget entries
tagline: The alert email your bank sends for each charge becomes an Actual Budget transaction
docs: /docs/flows/transaction-gmail-actual-budget
services:
  - EXIST_IS_SERVICES_ACTUAL_BUDGET
flows:
  - gmail
---

  1. Make a budget file: open https://actual-budget.<domain>, or
     ./existential.sh run actual-budget setup
  2. In Gmail, label your bank's alerts with a filter, then record the label:
     ./existential.sh run automation gmail-labels
  3. Every bank words its alerts differently: copy
     automation/lib/actual-budget/parse-chase.ts for yours, then wire the label to an account:
     ./existential.sh run automation gmail-transactions-cron
