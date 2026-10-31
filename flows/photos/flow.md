---
name: Photos
tagline: Immich with its admin made and your NAS photos already in it, read-only
docs: /docs/services/immich
services:
  - EXIST_IS_SERVICES_IMMICH
  - EXIST_IS_SERVICES_AUTOMATION
---

The migration creates the Immich admin (your EXIST_EMAIL and EXIST_PASSWORD) and adds the
photos on your NAS as a read-only External Library once Immich answers. Then open
https://immich.<domain> and sign in; the phone app takes the same login.
