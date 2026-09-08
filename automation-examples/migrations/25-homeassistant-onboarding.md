---
routine: homeassistant-onboarding
---

Complete Home Assistant's setup wizard headlessly, using HOMEASSISTANT_ADMIN_USER
/ HOMEASSISTANT_ADMIN_PASSWORD (services/homeassistant/.env.exist — same
EXIST_USERNAME login as every other service, with its own generated password).
Without this, https://homeassistant.<domain> redirects every page to the
onboarding wizard until a human creates an account by hand.

Safe to re-run — an instance that already has a user (onboarded by this
migration or by hand) is left alone. Copy to automation/migrations/ to
activate (the Core quest does this for you).
