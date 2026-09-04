---
routine: nextcloud-richdocuments
---

Install the `richdocuments` app in Nextcloud and point it at Collabora, so
Office documents open in Files instead of downloading.

Also sets `wopi_allowlist` to the `exist` bridge subnet (default
`172.16.0.0/12` — add a `WOPI_ALLOWLIST:` key above to override). Nextcloud's
own admin settings for this app warn when it is left blank — an empty
allowlist lets any IP that reaches Nextcloud make WOPI requests, not just the
actual Collabora container. See
automation/shared_routines/nextcloud-richdocuments.sh for the exact upstream
behaviour this was verified against.

COLLABORA_URL and the Nextcloud admin credentials come from the decree
container's own environment (services/automation/docker-compose.exist.yml),
rendered from nas/collabora/.env and nas/nextcloud/.env — nothing to set here.

Safe to re-run — install/enable is idempotent and the two config values are
just reset to the same value.

Requires nas/collabora (EXIST_IS_NAS_COLLABORA) enabled alongside nextcloud.
Copy to automation/migrations/ to activate.
