---
name: plugin-sharing
x-exist-project: automation
x-exist-title: Plugin sharing
x-exist-tagline: Ask another stack for one of its plugins, and send yours when asked, over the webhook
x-exist-docs: /docs/plugins
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
needs:
  - plugin_share
  - plugin_offer
  - plugin_request
---

Nothing is installed by an offer: what another stack sends lands in workspace/ai/proposed/,
and you accept it by moving it into notes/automations/. Which of your machines go out without
asking is PLUGIN_SHARE_ALLOW; every other one asks your phone first.
