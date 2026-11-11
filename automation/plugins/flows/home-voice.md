---
machine: plugin
automation: home-voice
name: Talk to the house
tagline: Home Assistant with speech in and out on CPU, and your own chat model answering what you ask
docs: /docs/services/homeassistant
services:
  - EXIST_IS_SERVICES_HOMEASSISTANT
  - EXIST_IS_AI_WYOMING_WHISPER
  - EXIST_IS_AI_WYOMING_PIPER
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - homeassistant_onboarding
  - homeassistant_voice
migrations:
  25-homeassistant-onboarding: |
    ---
    machine: homeassistant_onboarding
    ---

    Complete Home Assistant's setup wizard headlessly, using HOMEASSISTANT_ADMIN_USER
    / HOMEASSISTANT_ADMIN_PASSWORD (services/homeassistant/.env.exist — same
    EXIST_USERNAME login as every other service, with its own generated password).
    Without this, https://homeassistant.<domain> redirects every page to the
    onboarding wizard until a human creates an account by hand.

    Safe to re-run — an instance that already has a user (onboarded by this
    migration or by hand) is left alone. `./existential.sh flow on home-voice` activates it.
  26-homeassistant-voice: |
    ---
    machine: homeassistant_voice
    ---

    Wire up Home Assistant's voice pipeline headlessly: the two Wyoming
    integrations (wyoming-whisper, wyoming-piper), a conversation-agent entry
    pointed at the stack's chat model instead of raw OpenAI (via the
    `extended_openai_conversation` custom component
    `services/homeassistant/exist.initial.sh` installs), and an Assist pipeline
    tying all three together as the preferred one.

    Requires HA to have already picked up `extended_openai_conversation` — on a
    fresh install `exist.initial.sh` lands it before HA's first boot, so this
    just works; on an existing install, restart the `homeassistant` container
    once first. This migration fails loudly with that exact instruction if it
    isn't loaded yet, rather than guessing.

    Safe to re-run — existing Wyoming entries (matched by title), an existing
    conversation entry, and an existing "Local" pipeline are all left alone.
    `./existential.sh flow on home-voice` activates it.
---

The migrations create the admin account and the Assist pipeline once Home Assistant
answers. Then: https://homeassistant.<domain> → Settings → Voice assistants, and add
your devices from Home Assistant's own UI.
