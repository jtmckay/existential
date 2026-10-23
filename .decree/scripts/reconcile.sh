#!/usr/bin/env bash
# Migrations here are declarative: a migration is the desired state of its one
# concern, and changing it is how that concern changes. decree runs a migration
# once; this re-emits every processed one whose file no longer matches the copy
# develop's `record` kept in applied/ when it last landed, in ledger order.
set -euo pipefail
d="${DECREE_PROJECT_ROOT}/.decree"

n=0
while IFS= read -r f; do
  [ -n "${f}" ] && [ -f "${d}/migrations/${f}" ] || continue
  cmp -s "${d}/migrations/${f}" "${d}/applied/${f}" && continue
  decree emit --param spec="${f}" < "${d}/migrations/${f}"
  echo "reconcile: ${f} changed; queued for develop"
  n=$((n + 1))
done < "${d}/processed.md"
echo "reconcile: ${n} migration(s) queued"
