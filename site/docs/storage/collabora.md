---
sidebar_position: 4
---

# Collabora

- Source: https://github.com/CollaboraOnline/online
- License: [MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)
- Alternatives: OnlyOffice, LibreOffice Online

Document editor embedded in Nextcloud — LibreOffice running as a server.

## Domain Setup

Point the `collabora` subdomain in your DNS to Caddy, and ensure Caddy proxies to the Collabora container.

## Setup with Nextcloud

**Automatic**, if you copy `automation-examples/migrations/22-nextcloud-richdocuments.md`
into `automation/migrations/` — the `nextcloud-richdocuments` routine installs the app and
points it at this container for you (not part of Core's own copies, since Collabora isn't a
Core service — copy it yourself once both Nextcloud and Collabora are enabled). See
[Nextcloud → Collabora](./nextcloud#collabora-office-document-editing) for what that migration
does.

By hand instead:

1. In Nextcloud → Apps → search for **Nextcloud Office** (app id `richdocuments`; not
   "Collabora Online - Built-in CODE Server")
2. Install it
3. Go to Administration settings → **Office** → "Use your own server"
4. URL (and Port) of Collabora Online-server: `https://collabora.<domain>`

Nextcloud's own admin page also warns if its WOPI allow-list (`wopi_allowlist`) isn't set — that
restricts which IPs may call *Nextcloud's* WOPI endpoints and is configured on the Nextcloud side,
not here.

### WOPI host allowlist

`docker-compose.exist.yml` sets `aliasgroup1` (from `COLLABORA_NEXTCLOUD_DOMAIN` in `.env`,
defaulting to `nextcloud.$EXIST_DOMAIN`) so Collabora only ever trusts Nextcloud as a document
source. Without it, `coolwsd.xml`'s WOPI allowlist defaults to `mode="first"` — it trusts
whichever host's WOPI request reaches it *first* and locks to that host until restart, which on a
Caddy-fronted, publicly reachable Collabora is not guaranteed to be Nextcloud. `aliasgroup1` is
always set by the compose file, so this only bites if you remove that line.

No manual `trusted_proxies` step is needed for this integration — Nextcloud reapplies it (along
with `trusted_domains`, `overwritehost`, `overwriteprotocol`) from the environment on every start;
see `site/docs/storage/nextcloud.md`.
