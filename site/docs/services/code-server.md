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

## AI CLIs

`entrypoint.sh` installs `claude` (`@anthropic-ai/claude-code`) and `opencode` (`opencode-ai`)
via npm on first start, so both are available in the integrated terminal — this is a full
workstation, not just an editor. It also symlinks the dotfiles each one writes its login/auth
state to (`~/.claude`, `~/.claude.json`, `~/.local/share/opencode/auth.json`, …) onto the
`code_server_data` volume, so `claude login` / `opencode auth login` survive a container
recreation (`docker compose down && up`, an image rebuild, `./existential.sh reset`) instead of
silently forgetting and forcing you to re-authenticate.

`opencode.exist.json` is the default profile it copies into the workspace on first start,
pointed at `hermes-agent` — see [Hermes](../ai/hermes). It's a one-time copy: if you edit
`services/code-server/opencode.json` after that, the running container won't pick it up and
`exist.test.sh`/the container log will warn that the two have drifted.

## Notes

It runs on the shared `existential/decree:local` image rather than the upstream code-server
image, so it inherits the same toolchain every automation container has. There's no separate
image to maintain.

`code_server_data` holds the standalone code-server install and extensions (reinstallable, just
slow) as well as the AI CLI installs and login state above — not backed up; worst case for
either is redoing the install or logging back in.

Auth is a single shared password (`CODE_SERVER_PASSWORD`), not per-user accounts — a bare shell
in this container can read/write the whole `workspace/` and run the installed AI CLIs, so treat
that password like you would any other root-equivalent credential.
