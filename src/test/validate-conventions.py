#!/usr/bin/env python3
"""validate-conventions.py — verify slugs are wired consistently across
service compose files, piHole, Caddy, and dashy.

On-demand only: invoked via `./existential.sh validate`. NOT part of the
default test suite.

Conventions checked:
  1. Every container_name declared in a service compose appears as itself,
     not snake_case or camelCase (lowercase-hyphenated only).
  2. Every container_name starts with its folder's slug — so `docker ps`
     makes the service-membership obvious. (e.g., promtail in hosting/loki
     must be `loki-promtail`, not `promtail`.)
  3. Every piHole record (<slug>.internal) has a matching Caddy reverse_proxy
     block where the backend matches `<container_name>:<internal_port>`.
  4. Every piHole record has matching LOCAL active line + PEER commented line.
  5. Every Caddy block has a matching piHole record.
  6. Every dashy item points at a slug that has a piHole record.
  7. Every key in a service's `.env.example` starts with `<SLUG>_` where
     SLUG is the folder name uppercased (hyphens → underscores). Forces
     contributors to make the owning service obvious; image-required names
     (MYSQL_USER, POSTGRES_*, etc.) get mapped in docker-compose.yml.example.
     A file can opt out with a `# convention-exempt: upstream-env` marker
     in the first 5 lines — reserved for wholesale-copied upstream env
     templates loaded via `env_file:` (LibreChat, Immich).
  8. Every key in `.env.exist.example` starts with `EXIST_`, and the legacy
     `EXIST_DEFAULT_*` / `EXIST_ENABLE_*` prefixes are not used (use plain
     `EXIST_*` or `EXIST_IS_*` for service-enablement flags).
  9. Every volume in the master `docker-compose.yml` that declares
     `driver_opts: type: nfs` has the required NFS fields (`o: addr=…` and
     `device:`). Catches volumes that claim NFS but would actually fall back
     to a local Docker volume.

Note: container-to-container URLs in .env.example files use Docker service
DNS (`http://<container>:<port>`) and are NOT validated here. The `.internal`
convention is for browser/cross-machine traffic only.

Exit status: 0 if everything passes, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PIHOLE = REPO_ROOT / "hosting/pihole/docker-compose.yml.example"
CADDY = REPO_ROOT / "hosting/caddy/Caddyfile.example"
DASHY = REPO_ROOT / "services/dashy/dashy-conf.yml.example"
ENV_EXIST_EXAMPLE = REPO_ROOT / ".env.exist.example"
MASTER_COMPOSE = REPO_ROOT / "docker-compose.yml"

CATEGORY_DIRS = ("ai", "services", "hosting", "nas")

# KEY=VALUE line in a dotenv file (key only — value is whatever follows `=`).
ENV_KEY_LINE_RE = re.compile(r"^([A-Z_][A-Z0-9_]*)=")

# Match `container_name: foo-bar` at any indent.
CONTAINER_NAME_RE = re.compile(r"^\s*container_name:\s*([\w-]+)\s*$")
# Match port lines like `- "8080:80"` or `- 49621:9621` or `- "8931:8931"`.
PORT_LINE_RE = re.compile(
    r'^\s*-\s*"?(?:\${[^}]+}|\d+):(\d+)(?:/(?:tcp|udp))?"?\s*(?:#.*)?$'
)
# Caddy reverse_proxy line — accepts http:// prefix, port, optional braces.
CADDY_BLOCK_HEADER_RE = re.compile(r"^([\w.-]+)\.internal\s*\{")
CADDY_REVERSE_PROXY_RE = re.compile(
    r"^\s*reverse_proxy\s+(?:https?://)?([\w-]+):(\d+|\{[^}]+\})"
)
# piHole record line — `<IP> <slug>.internal` (optionally commented).
PIHOLE_RECORD_RE = re.compile(
    r"^\s*(?P<comment>#\s*)?\$\{(?P<var>EXIST_(?:LOCAL|PEER)_HOST_IP)\}\s+(?P<slug>[\w-]+)\.internal\s*$"
)
# Dashy url line — `url: https://<slug>.internal`.
DASHY_URL_RE = re.compile(r"^\s*url:\s*https?://([\w-]+)\.internal/?\s*$")
@dataclass
class ServiceDecl:
    slug: str
    file: Path
    line: int
    folder_slug: str = ""
    ports: list[tuple[int, int]] = field(default_factory=list)  # (host, container)


@dataclass
class PiHoleRecord:
    slug: str
    line: int
    has_local: bool = False
    has_peer_commented: bool = False


@dataclass
class CaddyBlock:
    slug: str
    backend_container: str
    backend_port: str
    line: int


@dataclass
class DashyItem:
    slug: str
    line: int


def parse_service_composes() -> dict[str, ServiceDecl]:
    """Walk every */*/docker-compose.yml.example, return slug → ServiceDecl."""
    services: dict[str, ServiceDecl] = {}
    for cat in CATEGORY_DIRS:
        for compose in (REPO_ROOT / cat).glob("*/docker-compose.yml.example"):
            folder_slug = compose.parent.name
            current_name: str | None = None
            current_decl: ServiceDecl | None = None
            for lineno, raw in enumerate(compose.read_text().splitlines(), start=1):
                if m := CONTAINER_NAME_RE.match(raw):
                    current_name = m.group(1)
                    current_decl = ServiceDecl(
                        slug=current_name,
                        file=compose,
                        line=lineno,
                        folder_slug=folder_slug,
                    )
                    services.setdefault(current_name, current_decl)
                    continue
                if current_decl is None:
                    continue
                if m := PORT_LINE_RE.match(raw):
                    container_port = int(m.group(1))
                    current_decl.ports.append((0, container_port))
    return services


def parse_pihole() -> dict[str, PiHoleRecord]:
    """Slug → PiHoleRecord. Confirms each slug has LOCAL + commented PEER."""
    records: dict[str, PiHoleRecord] = {}
    if not PIHOLE.exists():
        return records
    for lineno, raw in enumerate(PIHOLE.read_text().splitlines(), start=1):
        m = PIHOLE_RECORD_RE.match(raw)
        if not m:
            continue
        slug = m.group("slug")
        var = m.group("var")
        commented = m.group("comment") is not None
        rec = records.setdefault(slug, PiHoleRecord(slug=slug, line=lineno))
        if var == "EXIST_LOCAL_HOST_IP" and not commented:
            rec.has_local = True
        if var == "EXIST_PEER_HOST_IP" and commented:
            rec.has_peer_commented = True
    return records


def parse_caddy() -> dict[str, CaddyBlock]:
    """Slug → CaddyBlock with backend container + port."""
    blocks: dict[str, CaddyBlock] = {}
    if not CADDY.exists():
        return blocks
    current_slug: str | None = None
    current_line: int = 0
    for lineno, raw in enumerate(CADDY.read_text().splitlines(), start=1):
        if m := CADDY_BLOCK_HEADER_RE.match(raw):
            current_slug = m.group(1)
            current_line = lineno
            continue
        if current_slug and (m := CADDY_REVERSE_PROXY_RE.match(raw)):
            blocks[current_slug] = CaddyBlock(
                slug=current_slug,
                backend_container=m.group(1),
                backend_port=m.group(2),
                line=current_line,
            )
            current_slug = None
    return blocks


def parse_dashy() -> list[DashyItem]:
    """Every slug referenced in a dashy item's URL."""
    items: list[DashyItem] = []
    if not DASHY.exists():
        return items
    for lineno, raw in enumerate(DASHY.read_text().splitlines(), start=1):
        # Skip commented URL lines (the docs fallback)
        if raw.lstrip().startswith("#"):
            continue
        if m := DASHY_URL_RE.match(raw):
            items.append(DashyItem(slug=m.group(1), line=lineno))
    return items


def folder_slug_to_env_prefix(slug: str) -> str:
    """Convert a folder slug (lowercase-hyphenated) into the env-var prefix
    contributors must use in that service's `.env.example`.

    `actual-budget` → `ACTUAL_BUDGET_`
    `open-webui`    → `OPEN_WEBUI_`
    `hermes`        → `HERMES_`
    """
    return slug.replace("-", "_").upper() + "_"


def env_file_keys(path: Path) -> list[tuple[int, str]]:
    """Return [(lineno, key)] for every KEY=VALUE line in a dotenv file."""
    out: list[tuple[int, str]] = []
    if not path.exists():
        return out
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        stripped = raw.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        if m := ENV_KEY_LINE_RE.match(raw):
            out.append((lineno, m.group(1)))
    return out


def check_service_env_prefixes() -> list[str]:
    """Rule 7: every key in `<cat>/<slug>/.env.example` starts with the
    folder's slug uppercased. Excludes the top-level `.env.exist.example`.

    A file can opt out by including a top-of-file marker:
        # convention-exempt: upstream-env
    Use sparingly — only for env files copied wholesale from upstream
    projects (e.g., LibreChat, Immich) that load via `env_file:` and have
    too many keys to map individually in docker-compose.yml.example.
    """
    errors: list[str] = []
    for cat in CATEGORY_DIRS:
        for env_file in (REPO_ROOT / cat).glob("*/.env.example"):
            try:
                head = env_file.read_text().splitlines()[:5]
            except OSError:
                continue
            if any("convention-exempt: upstream-env" in line for line in head):
                continue
            slug = env_file.parent.name
            prefix = folder_slug_to_env_prefix(slug)
            for lineno, key in env_file_keys(env_file):
                if not key.startswith(prefix):
                    errors.append(
                        f"{env_file.relative_to(REPO_ROOT)}:{lineno}: "
                        f"key '{key}' must start with '{prefix}' "
                        f"(map image-required names like MYSQL_USER in docker-compose.yml.example instead)"
                    )
    return errors


def check_top_level_env_keys() -> list[str]:
    """Rule 8: every key in `.env.exist.example` starts with `EXIST_`, and
    the legacy `EXIST_DEFAULT_*` / `EXIST_ENABLE_*` prefixes are forbidden."""
    errors: list[str] = []
    for lineno, key in env_file_keys(ENV_EXIST_EXAMPLE):
        if not key.startswith("EXIST_"):
            errors.append(
                f".env.exist.example:{lineno}: "
                f"key '{key}' must start with 'EXIST_'"
            )
            continue
        if key.startswith("EXIST_DEFAULT_"):
            new_key = "EXIST_" + key[len("EXIST_DEFAULT_"):]
            errors.append(
                f".env.exist.example:{lineno}: "
                f"key '{key}' uses the legacy DEFAULT prefix — rename to '{new_key}'"
            )
        elif key.startswith("EXIST_ENABLE_"):
            new_key = "EXIST_IS_" + key[len("EXIST_ENABLE_"):]
            errors.append(
                f".env.exist.example:{lineno}: "
                f"key '{key}' uses the legacy ENABLE prefix — rename to '{new_key}'"
            )
    return errors


def check_nfs_volumes() -> list[str]:
    """Rule 9: every volume in the master `docker-compose.yml` that declares
    `driver_opts: type: nfs` must have `o:` (with `addr=`) and `device:`.
    Catches partially-configured volumes that would silently fall back to a
    local Docker volume despite claiming NFS."""
    errors: list[str] = []
    if not MASTER_COMPOSE.exists():
        # No master compose yet — skip silently. The check runs after
        # `./existential.sh compose` has been executed at least once.
        return errors
    try:
        import yaml
    except ImportError:
        errors.append(
            "docker-compose.yml: PyYAML required to validate NFS volumes "
            "(pip install pyyaml)"
        )
        return errors

    try:
        data = yaml.safe_load(MASTER_COMPOSE.read_text()) or {}
    except yaml.YAMLError as e:
        errors.append(f"docker-compose.yml: failed to parse — {e}")
        return errors

    volumes = data.get("volumes") or {}
    for name, spec in volumes.items():
        if not isinstance(spec, dict):
            continue
        opts = spec.get("driver_opts") or {}
        if not isinstance(opts, dict):
            continue
        # We only care about volumes that claim NFS.
        if str(opts.get("type", "")).lower() != "nfs":
            continue
        o_field = str(opts.get("o", ""))
        device = str(opts.get("device", ""))
        if "addr=" not in o_field:
            errors.append(
                f"docker-compose.yml: volume '{name}' has type: nfs but "
                f"`o:` is missing `addr=…` — would fall back to a local volume"
            )
        if not device:
            errors.append(
                f"docker-compose.yml: volume '{name}' has type: nfs but "
                f"`device:` is empty"
            )
    return errors


def main() -> int:
    services = parse_service_composes()
    pihole = parse_pihole()
    caddy = parse_caddy()
    dashy_items = parse_dashy()

    errors: list[str] = []
    warnings: list[str] = []

    # ── (1) container_name format ──────────────────────────────────────────
    bad_name_re = re.compile(r"[A-Z_]")
    for slug, decl in services.items():
        if bad_name_re.search(slug):
            errors.append(
                f"{decl.file.relative_to(REPO_ROOT)}:{decl.line}: "
                f"container_name '{slug}' is not lowercase-hyphenated"
            )

    # ── (1b) container_name prefixed with folder slug ──────────────────────
    # So `docker ps` makes service-membership obvious.
    for slug, decl in services.items():
        if not decl.folder_slug:
            continue
        if slug == decl.folder_slug:
            continue  # primary container — slug-only is fine
        if not slug.startswith(f"{decl.folder_slug}-"):
            errors.append(
                f"{decl.file.relative_to(REPO_ROOT)}:{decl.line}: "
                f"container_name '{slug}' must start with '{decl.folder_slug}-' "
                f"(or equal '{decl.folder_slug}') so it's obvious which "
                f"service it belongs to"
            )

    # ── (2)+(3) piHole has both records, refs match Caddy ──────────────────
    for slug, rec in pihole.items():
        if not rec.has_local:
            errors.append(
                f"hosting/pihole/docker-compose.yml.example:{rec.line}: "
                f"slug '{slug}' has no active LOCAL_HOST_IP record"
            )
        if not rec.has_peer_commented:
            errors.append(
                f"hosting/pihole/docker-compose.yml.example:{rec.line}: "
                f"slug '{slug}' has no commented PEER_HOST_IP fallback line"
            )

    # ── (4) Caddy and piHole are mirror sets ───────────────────────────────
    pihole_slugs = set(pihole.keys())
    caddy_slugs = set(caddy.keys())

    for slug in pihole_slugs - caddy_slugs:
        errors.append(
            f"hosting/pihole/docker-compose.yml.example: "
            f"slug '{slug}.internal' has a DNS record but no Caddy reverse_proxy block"
        )
    for slug in caddy_slugs - pihole_slugs:
        errors.append(
            f"hosting/caddy/Caddyfile.example: "
            f"slug '{slug}.internal' has a Caddy block but no piHole record"
        )

    # ── (5) Caddy backend matches an actual container ──────────────────────
    container_to_ports = {
        slug: {p[1] for p in decl.ports} for slug, decl in services.items()
    }
    for slug, block in caddy.items():
        decl = services.get(block.backend_container)
        if decl is None:
            errors.append(
                f"hosting/caddy/Caddyfile.example:{block.line}: "
                f"'{slug}.internal' proxies to '{block.backend_container}' — "
                f"no service compose declares that container_name"
            )
            continue
        # Skip port comparison if the Caddy block uses a {$VAR}
        if block.backend_port.startswith("{"):
            continue
        try:
            port_int = int(block.backend_port)
        except ValueError:
            continue
        if decl.ports and port_int not in container_to_ports[block.backend_container]:
            warnings.append(
                f"hosting/caddy/Caddyfile.example:{block.line}: "
                f"'{slug}.internal' → {block.backend_container}:{port_int}, but "
                f"the compose file only publishes "
                f"{sorted(container_to_ports[block.backend_container])} "
                f"({decl.file.relative_to(REPO_ROOT)}:{decl.line}). "
                f"OK if the container exposes more than it publishes."
            )

    # ── (6) Dashy items point at known slugs ───────────────────────────────
    for item in dashy_items:
        if item.slug not in pihole_slugs:
            errors.append(
                f"services/dashy/dashy-conf.yml.example:{item.line}: "
                f"item references '{item.slug}.internal' but no piHole record exists"
            )

    # ── (7) Service env var keys start with `<SLUG>_` ──────────────────────
    errors.extend(check_service_env_prefixes())

    # ── (8) .env.exist.example keys start with EXIST_, no legacy prefixes ──
    errors.extend(check_top_level_env_keys())

    # ── (9) NFS-declared volumes in master compose are fully configured ────
    errors.extend(check_nfs_volumes())

    # ── Report ─────────────────────────────────────────────────────────────
    print(f"Services declared:    {len(services)}")
    print(f"piHole records:       {len(pihole)}")
    print(f"Caddy blocks:         {len(caddy)}")
    print(f"Dashy items:          {len(dashy_items)}")
    print()

    if warnings:
        print(f"Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"  - {w}")
        print()

    if errors:
        print(f"Errors ({len(errors)}):")
        for e in errors:
            print(f"  ✗ {e}")
        print()
        print("Validation FAILED. Fix the above to keep conventions in sync.")
        return 1

    print("Validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
