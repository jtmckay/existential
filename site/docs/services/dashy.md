---
sidebar_position: 2
---

# Dashy

- Source: https://github.com/Lissy93/dashy
- License: [MIT](https://opensource.org/license/mit)
- Alternatives: Homepage, Heimdall, Homarr, Organizr

![Dashy dashboard](./dashy.png)

## Setup

Enable it in `.env.shared` and run the setup script — `.env` and `dashy-conf.yml` are
rendered from their `*.exist.*` templates automatically:

```bash
EXIST_IS_SERVICES_DASHY=true    # in .env.shared
./existential.sh && docker compose up -d
```

## Three files, one of them yours

Dashy's config is the one place the stack bakes your domain into a file rather than passing
it as an environment variable — Dashy reads a static `conf.yml` and does no variable
substitution of its own. So that the baked value can never go stale, `dashy-conf.yml` is
**regenerated on every `./existential.sh` run**. Change `EXIST_DOMAIN` and every tile
follows on the next run; no `--force`, nothing to remember.

| File | Tracked? | Role |
|---|---|---|
| `dashy-conf.exist.yml` | yes | The template. Which services appear, in what sections. |
| `dashy-conf.yml` | no | Generated, and overwritten every run — until you claim it. |

### Claiming the file

Want it your way? Open `services/dashy/dashy-conf.yml` and change one line in the header:

```yaml
# EXIST_KEEP: false     →     # EXIST_KEEP: true
```

That's it. The file is now yours: `./existential.sh` will never overwrite it again, not
even with `--force`. Edit it freely.

The trade-off is the one you'd expect — a claimed file stops tracking `EXIST_DOMAIN`, and
new services won't add themselves to your dashboard. You're maintaining it by hand from
then on. To hand it back, set `EXIST_KEEP: false` (or delete the file) and the next run
regenerates it from the template.

To change what ships by default for everyone, edit `dashy-conf.exist.yml` instead — slugs
there must match a `reverse_proxy` backend in `hosting/caddy/Caddyfile.exist.Caddyfile`,
which `./existential.sh validate` enforces.

## Editing from the Dashy UI

Dashy's built-in config editor can normally write `conf.yml` back to disk. That is
**disabled here** (`appConfig.preventWriteToDisk`, plus a read-only mount): the file is
regenerated every run, so anything saved that way would vanish without warning. Claim the
file with `EXIST_KEEP: true` if you want durable edits. Per-browser local saves still work
for temporary tweaks.
