---
machine: plugin
automation: update-ubuntu
name: Update Ubuntu
tagline: Security updates daily, every other package update on Sundays at 01:00, and a reboot at 02:00 only when an update requires it
docs: /docs/hosting/updates#ubuntu
project: host
needs:
  - ubuntu_upgrade
---
It runs in a decree daemon on the host (host/.decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

One step needs root, once, after ./existential.sh has installed the flow:

  sudo bash host/.decree/lib/ubuntu_upgrade/setup.sh

It never upgrades the Ubuntu release: do-release-upgrade stays yours to schedule.
