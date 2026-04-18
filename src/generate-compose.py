#!/usr/bin/env python3
"""
Generate a unified docker-compose.yml from all enabled services.

Reads EXIST_ENABLE_*=true entries from <repo>/.env, finds the corresponding
docker-compose.yml for each enabled service, adjusts relative paths so they
resolve correctly from the repo root, then merges everything into one file.

Usage (inside decree-adhoc container):
    python3 /src/generate-compose.py /repo [output-filename]
"""

import os
import re
import sys
from pathlib import Path
import yaml


# ── .env parsing ──────────────────────────────────────────────────────────────

def load_env(path: str) -> dict[str, str]:
    env: dict[str, str] = {}
    try:
        with open(path) as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, _, value = line.partition('=')
                env[key.strip()] = value.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return env


# ── Service discovery ──────────────────────────────────────────────────────────

SKIP_DIRS = {'graveyard', '.git', 'site', 'src', 'automations', 'node_modules'}


def service_env_key(rel_path: str) -> str:
    """'ai/libreChat' → 'EXIST_ENABLE_AI_LIBRECHAT'"""
    return 'EXIST_ENABLE_' + re.sub(r'[^A-Z0-9]', '_', rel_path.upper())


def find_enabled_services(repo_root: str, env: dict[str, str]) -> list[str]:
    """
    Walk depth-2 directories, find docker-compose.yml files, return paths
    where the matching EXIST_ENABLE_* variable is 'true'.
    """
    enabled = []
    root = Path(repo_root)

    for top in sorted(root.iterdir()):
        if not top.is_dir() or top.name in SKIP_DIRS or top.name.startswith('.'):
            continue
        for sub in sorted(top.iterdir()):
            if not sub.is_dir():
                continue
            if (sub / 'docker-compose.yml').exists():
                rel = f"{top.name}/{sub.name}"
                if env.get(service_env_key(rel), 'false').lower() == 'true':
                    enabled.append(rel)

    return enabled


# ── Path adjustment ────────────────────────────────────────────────────────────

def adjust_volume(vol: str | dict, service_prefix: str) -> str | dict:
    """
    Adjust a volume entry so relative source paths are correct from repo root.

    Short form: "./data:/container:opts"  →  "./services/foo/data:/container:opts"
    Long form dict: {source: ./data, ...} → {source: services/foo/data, ...}
    Named volumes and absolute paths are unchanged.
    """
    if isinstance(vol, dict):
        src = vol.get('source', '')
        if src and not src.startswith('/'):
            vol = dict(vol)
            vol['source'] = os.path.normpath(os.path.join(service_prefix, src))
        return vol

    if not isinstance(vol, str) or ':' not in vol:
        return vol

    parts = vol.split(':')
    src = parts[0]

    # Absolute path or named volume (no slash, no dot prefix)
    if src.startswith('/') or (not src.startswith('.') and '/' not in src and src != '.'):
        return vol

    adjusted = os.path.normpath(os.path.join(service_prefix, src))
    parts[0] = f'./{adjusted}'
    return ':'.join(parts)


def adjust_build(build: str | dict | None, service_prefix: str) -> str | dict | None:
    if build is None:
        return None
    if isinstance(build, str):
        if build.startswith('/'):
            return build
        return './' + os.path.normpath(os.path.join(service_prefix, build))
    if isinstance(build, dict):
        build = dict(build)
        ctx = build.get('context')
        if ctx and not str(ctx).startswith('/'):
            build['context'] = './' + os.path.normpath(os.path.join(service_prefix, ctx))
    return build


def adjust_env_file(ef: str | list | None, service_prefix: str) -> str | list | None:
    if ef is None:
        return None
    if isinstance(ef, str):
        return ef if ef.startswith('/') else os.path.join(service_prefix, ef)
    return [
        f if isinstance(f, str) and f.startswith('/') else os.path.join(service_prefix, f)
        for f in ef
    ]


def adjust_service_paths(svc: dict, service_prefix: str) -> dict:
    svc = dict(svc)

    if 'volumes' in svc and svc['volumes']:
        svc['volumes'] = [adjust_volume(v, service_prefix) for v in svc['volumes']]

    if 'build' in svc:
        svc['build'] = adjust_build(svc['build'], service_prefix)

    if 'env_file' in svc:
        svc['env_file'] = adjust_env_file(svc['env_file'], service_prefix)

    return svc


# ── Merge ──────────────────────────────────────────────────────────────────────

def merge(repo_root: str, enabled: list[str]) -> dict:
    services: dict = {}
    volumes: dict = {}
    networks: dict = {}

    for rel_path in enabled:
        compose_path = os.path.join(repo_root, rel_path, 'docker-compose.yml')
        if not os.path.exists(compose_path):
            print(f'warning: {compose_path} not found — skipping', file=sys.stderr)
            continue

        with open(compose_path) as f:
            config = yaml.safe_load(f) or {}

        prefix = rel_path

        for name, svc in (config.get('services') or {}).items():
            services[name] = adjust_service_paths(svc or {}, prefix)

        for name, vol in (config.get('volumes') or {}).items():
            volumes.setdefault(name, vol)  # first definition wins

        for name, net in (config.get('networks') or {}).items():
            networks.setdefault(name, net)

    # Ensure the shared exist network is present
    networks.setdefault('exist', {'driver': 'bridge'})

    result: dict = {}
    if services:
        result['services'] = services
    if volumes:
        result['volumes'] = volumes
    result['networks'] = networks

    return result


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) < 2:
        print('Usage: generate-compose.py <repo_root> [output-filename]', file=sys.stderr)
        sys.exit(1)

    repo_root = sys.argv[1]
    output_name = sys.argv[2] if len(sys.argv) > 2 else 'docker-compose.yml'
    output_path = os.path.join(repo_root, output_name)

    env = load_env(os.path.join(repo_root, '.env'))
    enabled = find_enabled_services(repo_root, env)

    if not enabled:
        print('No services enabled — set EXIST_ENABLE_*=true in .env', file=sys.stderr)
        sys.exit(0)

    print(f"Enabled ({len(enabled)}): {', '.join(enabled)}", file=sys.stderr)

    merged = merge(repo_root, enabled)

    with open(output_path, 'w') as f:
        f.write('# Generated by existential.sh — do not edit manually\n')
        yaml.dump(merged, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f'Written: {output_path}', file=sys.stderr)


if __name__ == '__main__':
    main()
