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
