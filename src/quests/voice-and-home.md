---
name: Voice & Home
tagline: Home Assistant runs the house; whisper and piper let you talk to it, and the agent answers
e2e: false
services:
  - var: EXIST_IS_SERVICES_HOMEASSISTANT
    label: Home Assistant (the house)
  - var: EXIST_IS_AI_WYOMING_WHISPER
    label: wyoming-whisper (speech to text)
  - var: EXIST_IS_AI_WYOMING_PIPER
    label: wyoming-piper (text to speech)
done:
  files:
    - volumes/workspace_data/.decree/migrations/25-homeassistant-onboarding.md
    - volumes/workspace_data/.decree/migrations/26-homeassistant-wyoming-hermes.md
---

Home Assistant is the house; whisper turns speech into text and piper turns
text back into speech, both on CPU so they never evict the chat model from the
card. The Assist pipeline ties them to Hermes, so asking the house a question
reaches your own agent. Core does not install any of it — Home Assistant
usually has a box of its own — and the voice pipeline needs the **Local AI**
quest's Hermes to answer.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_HOMEASSISTANT=true
       EXIST_IS_AI_WYOMING_WHISPER=true
       EXIST_IS_AI_WYOMING_PIPER=true

       ./existential.sh
       docker compose up -d

`exist.initial.sh` installs the extended_openai_conversation integration
before the container starts — that is what lets a conversation agent point at
the Hermes gateway instead of at OpenAI.

── 2. Create the admin account ───────────────────────────────────────────

Without this, https://homeassistant.${EXIST_DOMAIN} redirects every page to the
setup wizard until a human fills it in. The migration creates it from
EXIST_USERNAME / the generated password:

       mkdir -p volumes/workspace_data/.decree/migrations/
       cp automation-examples/migrations/25-homeassistant-onboarding.md \
          volumes/workspace_data/.decree/migrations/

(Or skip it and click through the wizard yourself — the migration then finds an
account already there and does nothing.)

── 3. Wire up the voice pipeline ─────────────────────────────────────────

This registers the two Wyoming services, adds a conversation agent pointed at
Hermes, and builds the Assist pipeline that chains them. It needs the account
from step 2 to exist first, which the numbering guarantees:

       cp automation-examples/migrations/26-homeassistant-wyoming-hermes.md \
          volumes/workspace_data/.decree/migrations/

Migrations run once each, in order, each waiting until Home Assistant
answers. Watch them with `docker exec automation decree status`.

── 4. Try it ─────────────────────────────────────────────────────────────

Open https://homeassistant.${EXIST_DOMAIN} → Settings → Voice assistants. The
pipeline should already be there with whisper as STT, piper as TTS and Hermes
as the conversation agent. Hit the microphone and ask it something only your
agent would know.

       ./existential.sh test homeassistant wyoming-whisper wyoming-piper

── 5. Add the house itself ───────────────────────────────────────────────

Devices are Home Assistant's business, not this stack's — add integrations from
its own UI. What this quest guarantees is that whatever you add is reachable by
voice and by the agent.

── What to build on this ─────────────────────────────────────────────────

A custom wake word on your phone, and Tasker on the other end: the
**Wake Word & Voice Triggers** quest. Routines that react to house events on a
schedule: the **Automation** slice of Core.
