---
name: repo
x-exist-project: host
needs:
  - decree_order
---
# repo

What the machines that develop this repo (`repo_develop`, `repo_qa`, each extending decree's
official plugin of that kind) share: decree's `decree_order`, which runs the repo's own
migrations, the order files in `.decree/machines/repo_develop/order/`, at each daemon start,
once each, and again when one is edited.
