#!/usr/bin/env bash
# Check or apply each line of requirements, as Ansible applies a play: `check` reports
# each resource ok or missing and changes nothing; `apply` installs a missing one and
# checks it again (changed), and stops at the first that fails, naming it.
# Usage: run.sh check|apply
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=${1:?usage: run.sh check|apply}
# One stream, so a failure prints after the lines before it.
exec 2>&1

missing=0
while read -r kind name version source; do
  [[ -z ${kind} || ${kind} == \#* ]] && continue
  label="${kind} ${name}${version:+ ${version}}"
  [ -f "${here}/kinds/${kind}.sh" ] || { echo "FAILED   ${label}: no kinds/${kind}.sh" >&2; exit 1; }
  # A subshell keeps one kind's functions from the next.
  # shellcheck source=/dev/null
  if (. "${here}/kinds/${kind}.sh" && check "${name}" "${version}" "${source}"); then
    echo "ok       ${label}"
  elif [ "${mode}" = check ]; then
    echo "missing  ${label}"
    missing=1
  elif (. "${here}/kinds/${kind}.sh" && install "${name}" "${version}" "${source}" &&
    check "${name}" "${version}" "${source}"); then
    echo "changed  ${label}"
  else
    echo "FAILED   ${label}" >&2
    exit 1
  fi
done < "${here}/requirements"
exit "${missing}"
