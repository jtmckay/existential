---
machine: plugin
automation: worker
name: Worker
tagline: This host's disks and automations, reported to your controller every 5 minutes, for Grafana's Hosts dashboard
docs: /docs/hosting/controller-and-workers
project: host
needs:
  - reporting
---
It runs in a decree daemon on the host (host/.decree): start one, and have it start at boot,
as https://existential.company/docs/hosting/host-daemon says.

With EXIST_CONTROLLER in .env.shared naming your controller (its tailnet name or 100.x
address), this host reports there. Blank, this host is the controller: the others ask it
where to report, and it names the Loki in EXIST_REPORTING_URL, or its own when Loki is on here.
