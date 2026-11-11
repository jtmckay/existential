---
machine: plugin
automation: office-documents
name: Office documents in Nextcloud
tagline: Open and edit Word, Excel and PowerPoint files in the browser, through Collabora
docs: /docs/storage/collabora
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_NAS_COLLABORA
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - nextcloud_richdocuments
migrations:
  22-nextcloud-richdocuments: |
    ---
    machine: nextcloud_richdocuments
    ---

    Install the `richdocuments` app in Nextcloud and point it at Collabora, so
    Office documents open in Files instead of downloading.

    Also sets `wopi_allowlist` to the `exist` bridge subnet (default
    `172.16.0.0/12` — add a `WOPI_ALLOWLIST:` key above to override). Nextcloud's
    own admin settings for this app warn when it is left blank — an empty
    allowlist lets any IP that reaches Nextcloud make WOPI requests, not just the
    actual Collabora container. And sets `wopi_callback_url` to `http://nextcloud`, so
    Collabora fetches files over the `exist` network, where that allowlist lets
    it in, rather than through the public URL. See
    automation/scripts/nextcloud_richdocuments.sh for the exact upstream
    behaviour this was verified against.

    COLLABORA_URL and the Nextcloud admin credentials come from the decree
    container's own environment (services/automation/docker-compose.exist.yml),
    rendered from nas/collabora/.env and nas/nextcloud/.env — nothing to set here.

    Safe to re-run — install/enable is idempotent and the two config values are
    just reset to the same value.

    Requires nas/collabora (EXIST_IS_NAS_COLLABORA) enabled alongside nextcloud.
    `./existential.sh flow on office-documents` activates it.
---
