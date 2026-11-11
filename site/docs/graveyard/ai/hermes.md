---
sidebar_position: 7
---

# Hermes

- Source: https://github.com/NousResearch/hermes-agent
- License: [MIT](https://opensource.org/licenses/MIT)
- Status: RIP — replaced by [pi](../../ai/pi.md)

An agent gateway with an OpenAI-compatible API, a dashboard and per-profile toolsets. It was the
stack's agent until 2026-10: a 1 GB container, a build cache extracted from its image, a ~17k-token
system prompt per call, and a config file the stack had to keep reconciling with `.env.shared`.

pi does the same work as a CLI in the decree image: profiles became
[departments](../../ai/pi.md#departments), the `/hermes/*` webhook endpoints became nothing (pi
runs inside `automation`), and Open WebUI and Home Assistant talk to the chat model directly.
The service folder is `graveyard/hermes/`.
