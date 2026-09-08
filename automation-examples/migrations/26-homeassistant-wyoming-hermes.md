---
routine: homeassistant-wyoming-hermes
---

Wire up Home Assistant's voice pipeline headlessly: the two Wyoming
integrations (wyoming-whisper, wyoming-piper), a conversation-agent entry
pointed at Hermes instead of raw OpenAI (via the `extended_openai_conversation`
custom component `services/homeassistant/exist.initial.sh` installs), and an
Assist pipeline tying all three together as the preferred one.

Requires HA to have already picked up `extended_openai_conversation` — on a
fresh install `exist.initial.sh` lands it before HA's first boot, so this
just works; on an existing install, restart the `homeassistant` container
once first. This migration fails loudly with that exact instruction if it
isn't loaded yet, rather than guessing.

Safe to re-run — existing Wyoming entries (matched by title), an existing
Hermes conversation entry, and an existing "Hermes" pipeline are all left
alone. Copy to automation/migrations/ to activate (the Core quest does this
for you).
