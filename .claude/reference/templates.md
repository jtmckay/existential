# Templates, placeholders & env vars

`./existential.sh` renders each enabled service's `*.exist.*` templates into live files.
`templates.sh` renders a destination **once** and skips it thereafter — that's what preserves
user edits and prompted answers. `--force` re-renders existing files; a rendered `.env` is never
overwritten even then.

## Placeholders (in `*.exist.*` templates)

- `EXIST_CLI` — prompts the user.
- `EXIST_24_CHAR_PASSWORD` / `EXIST_32_CHAR_HEX_KEY` — generate secrets.
- bare `EXIST_*` — pulls the matching var from root `.env.shared`.

An `EXIST_CLI` line can fall back to another var with a `# DEFAULT_FROM: EXIST_FOO` comment
directly above it (used if the user enters blank). Add a new generator only when a template
actually needs it — three unused ones (`EXIST_64_CHAR_HEX_KEY`, `EXIST_UUID`,
`EXIST_TIMESTAMP`) were carried for nothing and removed.

`EXIST_NIP_DOMAIN` renders `<EXIST_LOCAL_HOST_IP with dots→dashes>.nip.io` — public wildcard DNS
that maps the name back to that IP, so `<slug>.<domain>` resolves on every LAN device with no
pihole and no `/etc/hosts`. It is the `EXIST_DOMAIN` default. Resolved **after** the `EXIST_CLI`
pass, so `EXIST_LOCAL_HOST_IP` must appear *above* it in the template; falls back to
`x.internal` when no valid IPv4 is set. pihole stays supported and becomes a pure upgrade (it
answers the same wildcard locally, dropping the internet-DNS dependency); `.internal` domains
still require it, which `_warn_if_no_gateway` checks.

## Always-rendered files

`_ALWAYS_RENDER` in `src/templates.sh` is the carve-out to the render-once rule: a short list of
destinations regenerated on **every** run, `--force` or not.

**A file only qualifies when its render is a pure function of (template + `.env.shared`)** — no
secrets, no `EXIST_CLI`. Otherwise re-running loses information: a prompt would re-ask every
run, and a regenerated secret would rotate out from under whatever already consumed it.
`_assert_always_render_safe` enforces this and hard-fails the render, so the list can't silently
go wrong. The `.env` never-overwrite guard is checked *first* and still wins.

Use it when an app reads a static config file it can't env-substitute, so a value like
`EXIST_DOMAIN` would otherwise be baked once and go stale. `services/dashy/dashy-conf.yml` is
the only entry today.

Three things come with it:

- **A `DO NOT EDIT` header** is stamped on the output naming the template. `check-drift.ts` keys
  off that exact marker string (`isGenerated`) to skip these files rather than keeping its own
  copy of the list — keep the two in sync.
- **The user opts out by flipping `# EXIST_KEEP: false` to `true`** in that header
  (`_render_opted_out`). The file is then theirs permanently: never regenerated, and `--force`
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
