#!/usr/bin/env bash
# newsletter's deliver: copy the run's issue.md to NEWSLETTER_DIR/<YYYY-MM-DD>.md (-2,
# -3 when that day already has an issue), record every gathered link in
# $DECREE_STORE/seen.tsv with the date, and send the issue's first lines as a
# notification. Safe to re-run: an identical issue is not copied twice, and a link
# already in seen.tsv is not added again.
#
# Written straight to disk, so Nextcloud shows it but no file event fires.
set -euo pipefail
dir="$DECREE_DATA_NEWSLETTER_DIR"
issue="${DECREE_RUN_DIR}/issue.md"
items="${DECREE_RUN_DIR}/items.jsonl"
today="$(date +%F)"
mkdir -p "${dir}"

# The day's file name: the first free one, or the one already holding this issue.
target="${dir}/${today}.md"
n=1
while [ -e "${target}" ] && ! cmp -s "${issue}" "${target}"; do
  n=$((n + 1))
  target="${dir}/${today}-${n}.md"
done
cp "${issue}" "${target}"
echo "deliver: ${target}"

seen="${DECREE_STORE}/seen.tsv"
touch "${seen}"
added=0
if [ -s "${items}" ]; then
  while IFS= read -r link; do
    if ! cut -f1 "${seen}" | grep -qxF -- "${link}"; then
      printf '%s\t%s\n' "${link}" "${today}" >> "${seen}"
      added=$((added + 1))
    fi
  done < <(jq -r '.link' "${items}")
fi
echo "deliver: ${added} links added to ${seen}"

head -n 5 "${target}" | decree emit --machine notify \
  --param ntfy_title="Newsletter, ${today}" --param ntfy_tags=newspaper >/dev/null
