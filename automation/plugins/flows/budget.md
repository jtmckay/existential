---
name: budget
x-exist-project: automation
x-exist-title: Bank alerts become budget entries
x-exist-tagline: The alert email your bank sends for each charge becomes an Actual Budget transaction
x-exist-docs: /docs/flows/transaction-gmail-actual-budget
x-exist-services:
  - EXIST_IS_SERVICES_ACTUAL_BUDGET
needs:
  - actual_budget_parse
  - actual_budget
  - gmail-inbox
---

  1. Make a budget file: open https://actual-budget.<domain>, or
     ./existential.sh run actual-budget setup
  2. In Gmail, label your bank's alerts with a filter, then record the label:
     ./existential.sh run automation gmail-labels
  3. Every bank words its alerts differently: copy
     workspace/.decree/lib/actual-budget/parse-chase.ts (the actual_budget_parse plugin's) for yours, then wire the label to an account:
     ./existential.sh run automation gmail-transactions-cron
