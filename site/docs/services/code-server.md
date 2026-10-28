---
service: services/code-server
sidebar_position: 11
---

# code-server

- Source: https://github.com/coder/code-server
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Openvscode-server, JupyterLab, Gitpod

VS Code in the browser, over the workspace, from any device.

## Access

- Browser: `https://<machine>.<tailnet>.ts.net` over Tailscale (Core), or
  `https://code-server.EXIST_DOMAIN` with the Caddy add-on
- Password: `CODE_SERVER_PASSWORD` in `services/code-server/.env`

## Enable

Part of Core, so it ships on. If you turned it off:

```bash
EXIST_IS_SERVICES_CODE_SERVER=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

- First boot installs code-server, five extensions, Claude Code and opencode: a couple of
  minutes, `unhealthy` until done.
- About 210 MB idle; 1.3 GB peak during the first install. The 2 GB limit is headroom.

## Shared workspace

It mounts `workspace/`, the same tree [Hermes](../ai/hermes) sees at `/opt/data/workspace`, so
you and an agent can edit the same files at once.

## Seeing your flows

Open any graph in `.decree/graph/` and run **Markdown: Open Preview** to see it as a diagram
([Mermaid extension](https://open-vsx.org/extension/bierner/markdown-mermaid), installed on
boot).

## AI in the terminal

The terminal has `claude`, `opencode` and `hermes`. Talking to one is how you make new
automations. Machines have their own Claude login: [Decree](../decree/#claude-for-machines).

**`claude`** is Claude Code. Log in once; to keep the conversation going from your phone, start
a remote-control session in tmux:

```bash
tmx -d claude claude remote-control   # starts it, unless one is already running
tmx claude                            # attach to it
```

`tmx` never starts a second copy.

**`opencode`** is pointed at the stack's chat model on every boot (`EXIST_MODEL_URL_CHAT`, else
`EXIST_MODEL_URL`, and `EXIST_MODEL_CHAT`). Your `~/.config/opencode/opencode.json` is merged over it.

**What you type into `claude` and `opencode` is captured** to `workspace/.capture/` (secrets
redacted, never responses). `CODE_SERVER_CAPTURE=false` turns it off. See
[Capture](../getting-started#capture).

**No telemetry.** code-server runs with `--disable-telemetry`, Claude Code with
`DISABLE_TELEMETRY` and `DISABLE_ERROR_REPORTING`, opencode with sharing off. Your conversation
goes to the AI provider you use, under its terms.

**`hermes "..."`** sends one prompt to the stack's agent. It's `automation/lib/hermes-cli.sh`,
the same wrapper decree scripts use. Hermes reaches OpenViking, Firecrawl and Playwright itself:

```bash
hermes "what is still open in workspace/notes/plan.md?"
cat notes.md | hermes                     # prompt on stdin
hermes --profile research "..."           # one department's toolset
```

It uses `HERMES_API_KEY`. With hermes disabled it says so.

It isn't the upstream hermes CLI: one prompt, one answer, no session. The interactive TUI
(`hermes chat`) runs only inside `hermes-agent`. From a shell on the host:

```bash
docker exec -it hermes-agent /opt/hermes/.venv/bin/hermes chat
docker exec -it -e HERMES_HOME=/opt/data/profiles/research hermes-agent \
    /opt/hermes/.venv/bin/hermes chat     # one department
```

In the browser, the equivalents are the [Hermes dashboard](../ai/hermes) (sessions, skills,
agent config) and [Open WebUI](../ai/open-web-ui) (conversation).

**Installs and logins persist** on the `code_server_data` volume: npm's global prefix,
`~/.config`, `~/.local`, `~/.cache` and Claude Code's config all live there.

A tool that keeps state elsewhere (`~/.mytool/`, `~/mytool.json`) needs one step before you log
in:

```bash
docker exec code-server mkdir -p /code-server-data/home/.mytool
docker exec code-server touch   /code-server-data/home/mytool.json
```

Anything in `/code-server-data/home/` is linked into `$HOME` on every boot.

This container mounts `workspace/`, not the repo. Edit the stack on the host.

## Notes

- Runs on the shared `existential/decree:local` image, with the same toolchain as the
  automation containers.
- `code_server_data` (installs, extensions, logins) isn't backed up; losing it means reinstalling
  and logging in again.
- One shared password, `CODE_SERVER_PASSWORD`. Its shell can read and write all of `workspace/`
  and reach hermes, so treat it as root-equivalent.
