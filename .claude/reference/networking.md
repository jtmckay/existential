# Networking

There are two paths to a browser, and **Core uses Tailscale**.

**Core: `tailscale serve` on the tailnet name.** Core's two web apps need a certificate every
device already trusts (code-server's webviews and the ntfy phone app refuse a warning), and a
private CA means a root install on every device. So code-server and ntfy publish
`127.0.0.1:42080` / `127.0.0.1:44680` — loopback only, nothing in Core listens on the LAN — and
`_tailscale_serve_core` in `existential.sh` puts them on `https://<machine>.<tailnet>.ts.net` and
`:8443` with `tailscale serve --bg` (persists across reboots; re-setting a port replaces its
handler, and it skips one already set). It fills `EXIST_TAILNET_NAME` once serving works (fill
only); ntfy's entrypoint builds its base URL from it and the digest links to it. It **never runs
sudo and never fails**: no binary, not logged in, MagicDNS/HTTPS off (`CertDomains` empty) or
no operator (`sudo tailscale set --operator=$USER`) each print the next step and the run goes on.
`src/test/unit/test-remote-access.sh` drives it against a stub `tailscale`. Serve gives one
hostname per node, so it stays Core's two apps on two ports; per-service tailscale sidecars
would mean a node per container, which breaks "adding a service is adding a folder".

**The Caddy add-on: `<slug>.<domain>`.** For a host without Tailscale, or add-ons that each want
a name. Caddy ships **off**. The hostname suffix is `EXIST_DOMAIN`, defaulting to
`EXIST_NIP_DOMAIN` → `<host-ip-with-dashes>.nip.io`, which public wildcard DNS resolves back to
that IP — so `<slug>.<domain>` works on every device with **no piHole and no `/etc/hosts`**.
Nothing is asked at setup: `_ensure_host_access` detects the IP and derives the domain. Set it to
`x.internal` (piHole required, fully offline, and a second stack can take `y.internal`) or to a
domain you own — a value already present is never overwritten. `_detect_host_ip` takes the
address the kernel routes the internet through, except that a tailnet address that is up wins
(`tailscale ip -4`, range-checked against `100.64.0.0/10`). Remote access to Caddy's names is
any VPN (`site/docs/hosting/vpn.md` lists them side by side). Split the two jobs: **nip.io
supplies the wildcard**, the network supplies the reachability — the name resolves publicly,
but a LAN or CGNAT address only routes inside that network. **Never use a MagicDNS name as
`EXIST_DOMAIN`**: MagicDNS answers exact node names only, so `<slug>.<node>.ts.net` is NXDOMAIN
and the whole convention collapses (`_warn_if_no_gateway` catches `*.ts.net` and says so).

**Caddy's `Caddyfile.exist.Caddyfile` is the single source of truth for which `<slug>.<domain>`
hostnames exist** — `validate conventions` keys off it.

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

## Auth at the edge (only where the service can't)

`firecrawl` is gated in `Caddyfile.exist.Caddyfile` itself with a bearer token — self-hosted
firecrawl accepts any key, so without it the scraper is an open proxy. It **fails closed**: a
blank credential matches nothing and the host 401s. That is the pattern to copy — never a config
that errors, because a Caddyfile that fails to load takes every hostname down, not one. Note
`basic_auth` is not available that way: it needs a bcrypt hash, and neither `templates.sh` (token
substitution only) nor an `exist.initial.sh` (they run *after* the master `.env` is assembled) can
produce one for Caddy's environment in the same run.

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
