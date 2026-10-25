---
name: Talk to the house
tagline: Home Assistant with speech in and out on CPU, and Hermes answering what you ask
docs: /docs/services/homeassistant
services:
  - EXIST_IS_SERVICES_HOMEASSISTANT
  - EXIST_IS_AI_WYOMING_WHISPER
  - EXIST_IS_AI_WYOMING_PIPER
  - EXIST_IS_AI_HERMES
  - EXIST_IS_SERVICES_AUTOMATION
---

The migrations create the admin account and the Assist pipeline once Home Assistant
answers. Then: https://homeassistant.<domain> → Settings → Voice assistants, and add
your devices from Home Assistant's own UI.
