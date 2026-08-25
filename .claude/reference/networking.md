# Networking

The hostname suffix is `EXIST_DOMAIN`, defaulting to `EXIST_NIP_DOMAIN` →
`<lan-ip-with-dashes>.nip.io`, which public wildcard DNS resolves back to that IP — so
`<slug>.<domain>` works on every LAN device with **no piHole and no `/etc/hosts`**. Set it to
`x.internal` (piHole required, fully offline, and a second stack can take `y.internal`) or to a
domain you own. **Caddy's `Caddyfile.exist.Caddyfile` is the single source of truth for which
`<slug>.<domain>` hostnames exist** — `validate conventions` keys off it.

**DNS and TLS are independent choices.** piHole swaps public DNS for local (removing the
internet dependency); a real cert removes the trust step. Neither requires the other, and the
combination — owned domain + piHole + a DNS-01 wildcard cert — needs no public A record and no
inbound connectivity. See `site/docs/how-it-works.md`.

## Two addresses, two uses

- **Browser / cross-machine → `https://<slug>.<domain>`**: when piHole is enabled it resolves
  the *whole* domain with **one wildcard record**
  (`FTLCONF_misc_dnsmasq_lines: address=/${EXIST_DOMAIN}/${EXIST_LOCAL_HOST_IP}`) — no per-slug
  DNS entries. Caddy fronts each slug (stable pinned `*.<domain>` cert via `import internal_tls`
  — **not** `tls internal`; minted once by caddy's `exist.initial.sh` into `hosting/caddy/certs/`,
  so trust survives reboots and `caddy_data` wipes), reverse-proxies `<container>:<port>`; Dashy
  links navigable slugs.
- **Container-to-container → `http://<container>:<port>`** (Docker service DNS). Use this in
  service env vars and routine fallbacks (`${X_URL:-http://service:port}`) — faster, no TLS, no
  CA trust needed.

Adding a service only touches **Caddy** (and Dashy if navigable) — piHole's wildcard already
covers it. `validate conventions` verifies Dashy/Caddy stay in sync and the wildcard record
exists.

## Prefer runtime env over render-time baking

A bare `EXIST_DOMAIN` token is substituted *once*, when the file is rendered — and
`templates.sh` skips files that already exist, so the value goes stale. Resolve it at container
start instead, which makes swapping domains a one-line edit in `.env.shared`. (Where the app
genuinely can't read env, the fallback is to make the file always-render — see
`templates.md` — but runtime env is still the first choice: it needs no re-render at all.)

```yaml
# in docker-compose.exist.yml — derived from EXIST_DOMAIN, per-service override preserved
- CADDY_DOMAIN=${CADDY_DOMAIN:-$EXIST_DOMAIN}
- NTFY_BASE_URL=${NTFY_BASE_URL:-https://ntfy.$EXIST_DOMAIN}
```

Compose's `${VAR:-$OTHER}` chaining is verified to work. Where an app reads a config *file*,
check whether it also accepts env — ntfy maps every `server.yml` key to `NTFY_<KEY>` and env
wins, so its base-url lives in compose. Caddy reads `{$CADDY_DOMAIN}` from its container env, so
the Caddyfile never bakes a domain either.

For the exact `EXIST_DOMAIN` form to use per file type, see `templates.md`.

## Peer mode

Caddy + piHole on a separate front-door host: the front-door runs a tiny static
`Caddyfile.frontdoor.example` (copied to the live `Caddyfile`) that wildcard-forwards every
`<slug>.<domain>` to `EXIST_PEER_HOST_IP`, where a *second* Caddy runs the normal rendered
Caddyfile and routes to containers over Docker DNS. No per-slug peer config, no host-port
deconfliction — the front-door never changes as services are added.
