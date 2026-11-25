---
name: worker
x-exist-title: Worker
x-exist-tagline: This host's disks, CPU, RAM, VRAM, plugins and containers every 5 minutes, and every decree run as it happens, reported to your controller for Grafana
x-exist-docs: /docs/hosting/controller-and-workers
x-exist-project: host
needs:
  - reporting
---
It runs in a decree daemon on the host (the repo's own .decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

With EXIST_CONTROLLER in .env.shared naming your controller (its tailnet name or 100.x
address), this host reports there. Blank, this host is the controller: the others ask it
where to report, and it names its own Loki, which has to be on here.
