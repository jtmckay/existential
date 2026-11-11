---
machine: plugin
automation: photos
name: Photos
tagline: Immich with its admin made and your NAS photos already in it, read-only
docs: /docs/services/immich
services:
  - EXIST_IS_SERVICES_IMMICH
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - immich_setup
migrations:
  28-immich-setup: |
    ---
    machine: immich_setup
    ---

    Create Immich's admin from IMMICH_ADMIN_EMAIL / IMMICH_ADMIN_PASSWORD
    (services/immich/.env.exist: your EXIST_EMAIL and EXIST_PASSWORD), skip its onboarding
    wizard, and add `/mnt/media/external_photos` (the `immich_share` volume, read-only) as an
    External Library, scanned once now and nightly after. Without this,
    https://immich.<domain> opens on the admin sign-up page.

    Safe to re-run — an Immich that already has an admin (made by this migration or by hand) is
    left alone. `./existential.sh flow on photos` activates it.
---

The migration creates the Immich admin (your EXIST_EMAIL and EXIST_PASSWORD) and adds the
photos on your NAS as a read-only External Library once Immich answers. Then open
https://immich.<domain> and sign in; the phone app takes the same login.
