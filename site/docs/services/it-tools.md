---
sidebar_position: 5
---

# IT-Tools

- Source: https://github.com/CorentinTh/it-tools
- License: [GPL-3](https://www.gnu.org/licenses/gpl-3.0.html)
- Alternatives: CyberChef, DevUtils, Boop

A collection of handy developer utilities — a static single-page app with no backend, no
account, and no data of its own: everything runs client-side in the browser, so there's
nothing to configure or back up.

## Getting Started

Enable it, then bring the stack up from the repo root:

```bash
EXIST_IS_SERVICES_IT_TOOLS=true    # in .env.shared
./existential.sh && docker compose up -d
```

Reach it at `https://it-tools.<domain>` (Caddy + piHole required — see
[Hostnames that just work](../how-it-works#hostnames-that-just-work)); container-to-container,
it's `http://it-tools:80`.

## Examples

- Random port generator
- Text diff / JSON diff
- JSON prettify and format
- JSON to CSV
- Base64 encoder/decoder
- Case converter (lowercase, UPPERCASE, snake_case)
- JWT parser
- Regex tester and cheatsheet
- HTTP status codes reference
- ASCII art generator
