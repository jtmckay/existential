---
name: repo_qa
extends: decree_qa
x-exist-project: host
needs:
  - repo
  - decree_develop: repo_develop
---
# repo_qa

decree's `decree_qa`, for this repo: it attacks the repo and hands each real bug to
`repo_develop` as a failing test. It has no chaos suite of its own yet; one would be
`QA_RUN` in a `scripts/qa.sh` here.
