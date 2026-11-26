---
name: repo
x-exist-project: host
needs:
  - decree_order
  - decree_prune   # the host's runs, pruned like every project's (clean-runs is not the host's)
---
# repo

What the machines that develop this repo (`repo_develop`, `repo_qa`, each extending decree's
official plugin of that kind) share: decree's `decree_order`, which runs the repo's own
migrations, the order files in `.decree/machines/repo_develop/order/`, at each daemon start,
once each, and again when one is edited.
