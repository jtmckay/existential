---
sidebar_position: 11
---

# code-server

- Source: https://github.com/coder/code-server
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Openvscode-server, JupyterLab, Gitpod

VS Code in the browser. Useful for editing the stack — or anything in the shared workspace —
from a machine that isn't the one running it, including a tablet or phone.

## Access

- Browser: `https://code-server.EXIST_DOMAIN`
- Password: `CODE_SERVER_PASSWORD` in `services/code-server/.env`

## Enable

```bash
EXIST_IS_SERVICES_CODE_SERVER=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## Shared workspace

It mounts the repo's top-level `workspace/` directory, the same tree
[Hermes](../ai/hermes)' agent container sees at `/opt/data/workspace`. Edits made in the
browser and edits made by an agent land in the same files — that's the point of the shared
mount, and also the thing to be careful about when both are active.

Its own configuration cache (`code_server_data`) is tier 3: local, disposable, not backed up.

## Notes

It runs on the shared `existential/decree:local` image rather than the upstream code-server
image, so it inherits the same toolchain every automation container has. There's no separate
image to maintain.
