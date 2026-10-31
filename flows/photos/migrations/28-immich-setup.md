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
