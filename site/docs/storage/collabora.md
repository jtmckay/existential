---
service: nas/collabora
sidebar_position: 4
---

# Collabora

- Source: https://github.com/CollaboraOnline/online
- License: [MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)
- Alternatives: OnlyOffice, LibreOffice Online

Document editor embedded in Nextcloud — LibreOffice running as a server.

It runs in home mode (`--o:home_mode.enable=true`), so the editor fetches no welcome screen or
feedback popups from Collabora's servers. The cost is a cap of 20 connections and 10 open
documents, plenty for a household.

## Domain Setup

Point the `collabora` subdomain in your DNS to Caddy, and ensure Caddy proxies to the Collabora container.

## Setup with Nextcloud

**Automatic**: `./existential.sh flow on office-documents` asks to turn on Nextcloud and Collabora, and
its `nextcloud-richdocuments` migration installs the app and points it at this container. See
[Nextcloud → Collabora](./nextcloud#collabora-office-document-editing) for what that migration
does.

By hand instead:

1. In Nextcloud → Apps → search for **Nextcloud Office** (app id `richdocuments`; not
   "Collabora Online - Built-in CODE Server")
2. Install it
3. Go to Administration settings → **Office** → "Use your own server"
4. URL (and Port) of Collabora Online-server: `https://collabora.<domain>`
   and, under Advanced settings, the WOPI callback URL: `http://nextcloud`

Nextcloud's own admin page also warns if its WOPI allow-list (`wopi_allowlist`) isn't set — that
restricts which IPs may call *Nextcloud's* WOPI endpoints and is configured on the Nextcloud side,
not here.

### WOPI host allowlist

`docker-compose.exist.yml` sets `aliasgroup1` to Nextcloud's public URL (from
`COLLABORA_NEXTCLOUD_DOMAIN` in `.env`, defaulting to `nextcloud.$EXIST_DOMAIN`) and to
`http://nextcloud`, so Collabora only ever trusts Nextcloud as a document source. Without it,
`coolwsd.xml`'s WOPI allowlist defaults to `mode="first"` — it trusts whichever host's WOPI
request reaches it *first* and locks to that host until restart, which on a Caddy-fronted,
publicly reachable Collabora is not guaranteed to be Nextcloud.

Collabora fetches files from `http://nextcloud` because Nextcloud's `wopi_callback_url` says so.
Over the `exist` network its requests come from inside `wopi_allowlist`. Through the public URL
they would leave through Caddy (and Cloudflare, if fronted), come back from a LAN IP, and get a
403 that Collabora shows as "Unauthorized WOPI host".
Because Collabora then knows Nextcloud as `nextcloud`, `net.frame_ancestors` (in `extra_params`)
names the public host too: the browser embeds the editor in that page, and without it refuses
the frame ("Failed to load Nextcloud Office").

No manual `trusted_proxies` step is needed for this integration — Nextcloud reapplies it (along
with `trusted_domains`, `overwritehost`, `overwriteprotocol`) from the environment on every start;
see `site/docs/storage/nextcloud.md`.
