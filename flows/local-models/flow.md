---
name: Local models
tagline: Ollama on this machine pulls the models your VRAM tier names, once, as soon as it is up
docs: /docs/ai/ollama
services:
  - EXIST_IS_AI_OLLAMA
  - EXIST_IS_SERVICES_AUTOMATION
---

The models are named once, in .env.shared's Model Selection block; change them with
./existential.sh run models. To pull in the foreground instead:
  ./existential.sh run ollama pull-models
