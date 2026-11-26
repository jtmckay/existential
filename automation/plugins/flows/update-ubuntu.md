---
name: update-ubuntu
x-exist-title: Update Ubuntu
x-exist-tagline: Security updates daily, every other package update on Sundays at 01:00, and a reboot at 02:00 only when an update requires it
x-exist-docs: /docs/hosting/updates#ubuntu
x-exist-project: host
needs:
  - update_ubuntu
  - decree_prune   # the host's runs, pruned like every project's (clean-runs is not the host's)
---
It runs in a decree daemon on the host (the repo's own .decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

One step needs root, once, after ./existential.sh has installed the flow:

  sudo bash .decree/lib/update_ubuntu/setup.sh

It never upgrades the Ubuntu release: do-release-upgrade stays yours to schedule.
