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

Part of Core, so it is already on if you took that quest. Otherwise:

```bash
EXIST_IS_SERVICES_CODE_SERVER=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

First boot installs the code-server binary and four extensions before anything answers on
`:8080` — a couple of minutes, and it reports `unhealthy` until then. Measured after that:
~210 MB idle with no client connected (58 MB of it real RSS, the rest reclaimable page cache),
peaking at 1.3 GB during an install that also pulled two npm CLIs, so lighter now. The 2 GB
limit is headroom for an editing session, not the resting cost.

## Shared workspace

It mounts the repo's top-level `workspace/` directory, the same tree
[Hermes](../ai/hermes)' agent container sees at `/opt/data/workspace`. Edits made in the
browser and edits made by an agent land in the same files — that's the point of the shared
mount, and also the thing to be careful about when both are active.

## AI in the terminal

The stack puts one thing there and installs nothing else.

**`hermes "..."`** is the stack's own agent, one prompt at a time. It is
`automation/lib/hermes-cli.sh` — the same curl wrapper (`lib/hermes.sh`) every decree routine
uses — bind-mounted read-only at `/opt/hermes/` and symlinked onto `PATH` by `entrypoint.sh`, so
there is one implementation of "talk to hermes" rather than one per container. Hermes runs its
own tool loop, so it reaches OpenViking, Firecrawl and Playwright without any wiring here:

```bash
hermes "what is still open in workspace/notes/plan.md?"
cat notes.md | hermes                     # prompt on stdin
hermes --profile research "..."           # one department's toolset
```

It authenticates with `HERMES_API_KEY`, passed in by compose. With hermes disabled the command
says so rather than failing obscurely.

**It is not the upstream hermes CLI.** One prompt, one answer, no session and no history —
`hermes` with no arguments prints usage rather than pretending to be a REPL. The interactive TUI
(`hermes chat`, sessions, skills, slash commands) is a *local agent*: it reads its own
`HERMES_HOME`, config and MCP servers, so it only runs where those live — inside the
`hermes-agent` container. Reaching it from here would mean handing this container the Docker
socket, which is root on the host; run it from a shell on the machine instead:

```bash
docker exec -it hermes-agent /opt/hermes/.venv/bin/hermes chat
docker exec -it -e HERMES_HOME=/opt/data/profiles/research hermes-agent \
    /opt/hermes/.venv/bin/hermes chat     # one department
```

In the browser, the equivalents are the [Hermes dashboard](../ai/hermes) (sessions, skills,
agent config) and [Open WebUI](../ai/open-web-ui) (conversation).

**Your own CLI.** The container ships no AI coding agent and names none — install what you use
(`npm i -g <package>`) in the terminal. It sticks: `entrypoint.sh` symlinks npm's global prefix
and the XDG dirs (`~/.npm-global`, `~/.config`, `~/.local`, `~/.cache`) onto the
`code_server_data` volume, so both the install and its credentials survive a container
recreation (`docker compose down && up`, an image rebuild, `./existential.sh reset`) instead of
silently vanishing.

A tool that keeps state somewhere else — its own `~/.toolname/` or `~/.toolname.json` — needs
one setup step, once, before you log it in:

```bash
docker exec code-server mkdir -p /code-server-data/home/.mytool
docker exec code-server touch   /code-server-data/home/mytool.json
```

Anything already in `/code-server-data/home/` is linked into `$HOME` on every boot, so that is
the whole mechanism — no repo edit, nothing here to keep in step with your choice of tool.

Bear in mind this container only mounts `workspace/`, not the repo — editing the stack itself
happens on the machine that holds it.

## Notes

It runs on the shared `existential/decree:local` image rather than the upstream code-server
image, so it inherits the same toolchain every automation container has. There's no separate
image to maintain.

`code_server_data` holds the standalone code-server install and extensions (reinstallable, just
slow) as well as anything you installed in the terminal and its login state — not backed up;
worst case for either is redoing the install or logging back in.

Auth is a single shared password (`CODE_SERVER_PASSWORD`), not per-user accounts — a bare shell
in this container can read/write the whole `workspace/`, reach the hermes gateway and run
whatever is installed in it, so treat that password like you would any other root-equivalent
credential.
