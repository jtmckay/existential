# Templates, placeholders & env vars

`./existential.sh` renders each enabled service's `*.exist.*` templates into live files.
`templates.sh` renders a destination **once** and skips it thereafter — that's what preserves
user edits and prompted answers. There is no re-render flag: the old `--force` overwrote with no
undo and never said what it would touch. `./existential.sh reset` archives the rendered files to
`archive/<timestamp>/` instead, so the next run re-renders from a clean tree with everything
recoverable. A rendered `.env` is never overwritten in place at all.

## Placeholders (in `*.exist.*` templates)

- `EXIST_CLI` — prompts the user.
- `EXIST_24_CHAR_PASSWORD` / `EXIST_32_CHAR_HEX_KEY` — generate secrets.
- `EXIST_HOST_IP` — the host's LAN IP, detected rather than asked.
- `EXIST_NIP_DOMAIN` — a wildcard-DNS domain derived from it.
- bare `EXIST_*` — pulls the matching var from root `.env.shared`.

An `EXIST_CLI` line can fall back to another var with a `# DEFAULT_FROM: EXIST_FOO` comment
directly above it (used if the user enters blank). Add a new generator only when a template
actually needs it — three unused ones (`EXIST_64_CHAR_HEX_KEY`, `EXIST_UUID`,
`EXIST_TIMESTAMP`) were carried for nothing and removed.

**Keep the first run's prompt count near zero.** Anything the machine can determine, it should:
a prompt whose right answer is "press Enter" is not setup, and a blank answer to a prompt that
*matters* is worse than no prompt at all. `.env.exist.shared` is down to two `EXIST_CLI` lines
(`EXIST_EMAIL`, `EXIST_USERNAME`); the NFS trio ships blank and belongs to the NAS Storage quest.
Before adding an `EXIST_CLI`, check whether detection or a quest can carry it instead.

### The three ordered placeholders

These resolve in a fixed order, each feeding the next, all **after** the `EXIST_CLI` pass:

1. `EXIST_HOST_IP` → `$EXIST_DETECTED_HOST_IP`, passed in by `existential.sh`. `_detect_host_ip`
   prefers `tailscale ip -4` (validated against `100.64.0.0/10`, so an installed-but-down
   tailscale falls through) and otherwise uses `ip route get 1.1.1.1`. Detection **must** happen
   on the host: `templates.sh` runs inside the adhoc container, where both answer for the
   container. Non-IPv4 renders blank.
2. `EXIST_NIP_DOMAIN` → `<EXIST_LOCAL_HOST_IP with dots→dashes>.nip.io`. Public wildcard DNS that
   maps the name back to that IP, so `<slug>.<domain>` resolves on every device with no
   pihole and no `/etc/hosts`. It is the `EXIST_DOMAIN` default, and it reads `EXIST_LOCAL_HOST_IP`
   back out of the already-substituted content — so that key must appear *above* it in the
   template. Falls back to `x.internal`, which nothing resolves, when no valid IPv4 is set.
3. `_ensure_host_access` in `existential.sh`, after the render, as the upgrade path for a
   `.env.shared` that predates step 1 or was left blank.

`EXIST_LOCAL_HOST_IP` was an `EXIST_CLI` prompt until step 1 existed, and that ordering is the
whole point: a blank answer at prompt time meant `EXIST_NIP_DOMAIN` had nothing to build from,
`EXIST_DOMAIN` became `x.internal`, and `_ensure_host_access` then declined to overwrite it
(non-empty). The first run ended on a DNS warning. Both values are only ever **filled in, never
overwritten** — a deliberate `.internal` or owned domain survives. pihole stays supported and
becomes a pure upgrade (it answers the same wildcard locally, dropping the internet-DNS
dependency); `.internal` domains still require it, which `_warn_if_no_gateway` checks.

## Always-rendered files

`_ALWAYS_RENDER` in `src/templates.sh` is the carve-out to the render-once rule: a short list of
destinations regenerated on **every** run.

**A file only qualifies when its render is a pure function of (template + `.env.shared`)** — no
secrets, no `EXIST_CLI`. Otherwise re-running loses information: a prompt would re-ask every
run, and a regenerated secret would rotate out from under whatever already consumed it.
`_assert_always_render_safe` enforces this and hard-fails the render, so the list can't silently
go wrong. The `.env` never-overwrite guard is checked *first* and still wins.

Use it when an app reads a static config file it can't env-substitute, so a value like
`EXIST_DOMAIN` would otherwise be baked once and go stale. Two entries today:
`services/dashy/dashy-conf.yml` and `ai/honcho/config.toml` — honcho reads a TOML file with no
env substitution, so the `EXIST_MODEL_*` globals have to be rendered into it, and a model change
must land on the next ordinary run.

Three things come with it:

- **A `DO NOT EDIT` header** is stamped on the output naming the template. `check-drift.ts` keys
  off that exact marker string (`isGenerated`) to skip these files rather than keeping its own
  copy of the list — keep the two in sync.
- **The user opts out by flipping `# EXIST_KEEP: false` to `true`** in that header
  (`_render_opted_out`). The file is then theirs permanently: never regenerated, and `reset`
  won't touch it either. That is the whole customisation story — there is no override file and
  no merge engine. The toggle is a **comment**, so it stays valid in whatever format the
  destination is (a bare token would break the YAML dashy parses), and only the first 20 lines
  are inspected so the same words in the body mean nothing.
- **Write in place, never rename.** These files can be *single-file* bind mounts (dashy-conf.yml
  is), and `mv`/rename swaps the inode and detaches the running container's mount.
  `printf > "$dst"` truncates in place, which is why the archive-then-rename pattern
  `generate-compose.ts` uses for the root compose file must **not** be copied here.

If the app can read env, do that instead — see `networking.md` "Prefer runtime env over
render-time baking".

## Env var naming

- **Top-level** (`.env.exist.shared`): every key starts `EXIST_`. Enablement flags:
  `EXIST_IS_<CATEGORY>_<SLUG>=true|false`. Shared cross-service values live here, referenced as
  `${EXIST_FOO}` in compose files.
- **Per-service** (`<cat>/<slug>/.env.exist`): every key starts `<SLUG>_` (folder uppercased,
  hyphens → underscores). Image-required names get mapped in compose
  (`MYSQL_USER: ${MEALIE_MYSQL_USER}`). Wholesale upstream env files opt out with top-of-file
  `# convention-exempt: upstream-env`.

Both are checked by `./existential.sh validate conventions`.

## `EXIST_DOMAIN` form by file type

- compose `*.exist.yml` → `${EXIST_DOMAIN}` / `${SLUG_VAR:-…$EXIST_DOMAIN}` — **preferred**.
- rendered non-compose → bare `EXIST_DOMAIN` (render-substituted). **Last resort**, only when
  the app cannot read env. `dashy-conf.exist.yml` is the remaining case (Dashy reads a static
  `conf.yml` and does no substitution of its own); it is in `_ALWAYS_RENDER`, so a domain change
  propagates on the next plain `./existential.sh`. Note the bare-token sed rewrites **prose
  too** — don't name the variable in that file's comments or the name is replaced with its value.
- `.example` swap-ins (`Caddyfile.frontdoor.example`) → `{$EXIST_DOMAIN}` (Caddy expands from
  its container env). Never put `{$EXIST_DOMAIN}` in a rendered file — the bare-token sed would
  corrupt it.
