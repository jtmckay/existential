#!/usr/bin/env tsx
/**
 * Generate a unified docker-compose.yml from all enabled services.
 *
 * Reads EXIST_IS_*=true entries from <repo>/.env.shared, finds the corresponding
 * docker-compose.yml for each enabled service, adjusts relative paths so they
 * resolve correctly from the repo root, then merges everything into one file.
 *
 * Usage (inside existential-adhoc container):
 *   tsx /src/generate-compose.ts /repo [output-filename]
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// ── .env parsing ──────────────────────────────────────────────────────────────

function loadEnv(filePath: string): Record<string, string> {
  const env: Record<string, string> = {};
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    for (const raw of content.split('\n')) {
      const line = raw.trim();
      if (!line || line.startsWith('#') || !line.includes('=')) continue;
      const eqIdx = line.indexOf('=');
      const key = line.slice(0, eqIdx).trim();
      let value = line.slice(eqIdx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      env[key] = value;
    }
  } catch {
    // file not found — return empty
  }
  return env;
}

// ── Service discovery ──────────────────────────────────────────────────────────

const SKIP_DIRS = new Set(['graveyard', '.git', 'site', 'src', 'automations', 'node_modules', 'volumes']);

function serviceEnvKey(relPath: string): string {
  return 'EXIST_IS_' + relPath.toUpperCase().replace(/[^A-Z0-9]/g, '_');
}

function findEnabledServices(repoRoot: string, env: Record<string, string>): string[] {
  const enabled: string[] = [];
  const topEntries = fs.readdirSync(repoRoot, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name));

  for (const top of topEntries) {
    if (!top.isDirectory() || SKIP_DIRS.has(top.name) || top.name.startsWith('.')) continue;
    const topPath = path.join(repoRoot, top.name);
    const subEntries = fs.readdirSync(topPath, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name));

    for (const sub of subEntries) {
      if (!sub.isDirectory()) continue;
      const composePath = path.join(topPath, sub.name, 'docker-compose.yml');
      if (fs.existsSync(composePath)) {
        const rel = `${top.name}/${sub.name}`;
        if ((env[serviceEnvKey(rel)] ?? 'false').toLowerCase() === 'true') {
          enabled.push(rel);
        }
      }
    }
  }
  return enabled;
}

// ── Path adjustment ────────────────────────────────────────────────────────────

type VolumeEntry = string | Record<string, unknown>;

function adjustVolume(vol: VolumeEntry, servicePrefix: string): VolumeEntry {
  if (typeof vol === 'object' && vol !== null) {
    const src = vol['source'] as string | undefined;
    if (src && !src.startsWith('/')) {
      return { ...vol, source: path.normalize(path.join(servicePrefix, src)) };
    }
    return vol;
  }

  if (typeof vol !== 'string' || !vol.includes(':')) return vol;

  const parts = vol.split(':');
  const src = parts[0];

  // Absolute path or named volume (no leading dot or slash, and no directory separator)
  if (src.startsWith('/') || (!src.startsWith('.') && !src.includes('/') && src !== '.')) {
    return vol;
  }

  parts[0] = './' + path.normalize(path.join(servicePrefix, src));
  return parts.join(':');
}

function adjustBuild(
  build: string | Record<string, unknown> | null | undefined,
  servicePrefix: string,
): typeof build {
  if (build == null) return build;
  if (typeof build === 'string') {
    return build.startsWith('/') ? build : './' + path.normalize(path.join(servicePrefix, build));
  }
  if (typeof build === 'object') {
    const ctx = build['context'] as string | undefined;
    if (ctx && !ctx.startsWith('/')) {
      return { ...build, context: './' + path.normalize(path.join(servicePrefix, ctx)) };
    }
  }
  return build;
}

function adjustEnvFile(
  ef: string | string[] | null | undefined,
  servicePrefix: string,
): typeof ef {
  if (ef == null) return ef;
  if (typeof ef === 'string') {
    return ef.startsWith('/') ? ef : path.join(servicePrefix, ef);
  }
  return ef.map(f => (typeof f === 'string' && !f.startsWith('/')) ? path.join(servicePrefix, f) : f);
}

function adjustServicePaths(svc: Record<string, unknown>, servicePrefix: string): Record<string, unknown> {
  const out = { ...svc };
  if (Array.isArray(out['volumes'])) {
    out['volumes'] = (out['volumes'] as VolumeEntry[]).map(v => adjustVolume(v, servicePrefix));
  }
  if ('build' in out) {
    out['build'] = adjustBuild(out['build'] as string | Record<string, unknown>, servicePrefix);
  }
  if ('env_file' in out) {
    out['env_file'] = adjustEnvFile(out['env_file'] as string | string[], servicePrefix);
  }
  return out;
}

// ── Merge ──────────────────────────────────────────────────────────────────────

function merge(repoRoot: string, enabled: string[], networkExternal = false): Record<string, unknown> {
  const services: Record<string, unknown> = {};
  const volumes: Record<string, unknown> = {};
  const networks: Record<string, unknown> = {};

  for (const relPath of enabled) {
    const composePath = path.join(repoRoot, relPath, 'docker-compose.yml');
    if (!fs.existsSync(composePath)) {
      process.stderr.write(`warning: ${composePath} not found — skipping\n`);
      continue;
    }
    const config = (yaml.load(fs.readFileSync(composePath, 'utf8')) ?? {}) as Record<string, unknown>;

    for (const [name, svc] of Object.entries((config['services'] ?? {}) as Record<string, Record<string, unknown>>)) {
      services[name] = adjustServicePaths(svc ?? {}, relPath);
    }
    for (const [name, vol] of Object.entries((config['volumes'] ?? {}) as Record<string, unknown>)) {
      if (!(name in volumes)) volumes[name] = vol;  // first definition wins
    }
    for (const [name, net] of Object.entries((config['networks'] ?? {}) as Record<string, unknown>)) {
      if (!(name in networks)) networks[name] = net;
    }
  }

  // Always use the configured exist network definition, ignoring per-service declarations
  networks['exist'] = networkExternal ? { external: true } : { driver: 'bridge' };

  const result: Record<string, unknown> = {};
  if (Object.keys(services).length) result['services'] = services;
  if (Object.keys(volumes).length) result['volumes'] = volumes;
  result['networks'] = networks;
  return result;
}

// ── Master .env generation ─────────────────────────────────────────────────────

function mergeEnv(repoRoot: string, enabled: string[]): void {
  const merged: Record<string, string> = {};
  const paths = [
    path.join(repoRoot, '.env.shared'),
    ...enabled.map(r => path.join(repoRoot, r, '.env')),
  ];
  for (const p of paths) Object.assign(merged, loadEnv(p));

  const header = [
    '# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n',
    '# DO NOT EDIT — this file is auto-generated by existential.sh\n',
    '# Edit .env.shared (global) or service-level .env files instead\n',
    '# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n',
  ].join('');

  const envPath = path.join(repoRoot, '.env');
  fs.writeFileSync(envPath, header + Object.entries(merged).map(([k, v]) => `${k}=${v}\n`).join(''));
  process.stderr.write(`Written: ${envPath}\n`);
}

// ── NFS → bind-mount conversion ────────────────────────────────────────────────

// When NFS is not configured, replace NFS volumes with bind mounts pointing at
// <hostRepoRoot>/volumes/<name>.  The directory is also created under repoRoot
// (the adhoc-internal path) so Docker has a real directory to mount.
function convertNfsVolumes(
  merged: Record<string, unknown>,
  repoRoot: string,
  hostRepoRoot: string,
): void {
  const vols = merged['volumes'] as Record<string, unknown> | undefined;
  if (!vols) return;

  for (const [volName, volConfig] of Object.entries(vols)) {
    const cfg = volConfig as Record<string, unknown> | null;
    const driverOpts = cfg?.['driver_opts'] as Record<string, string> | undefined;
    if (driverOpts?.['type'] !== 'nfs') continue;

    const adHocDir = path.join(repoRoot, 'volumes', volName);
    fs.mkdirSync(adHocDir, { recursive: true });

    vols[volName] = {
      driver: 'local',
      driver_opts: {
        type: 'none',
        o: 'bind',
        device: path.join(hostRepoRoot, 'volumes', volName),
      },
    };
  }
}

// ── Entry point ────────────────────────────────────────────────────────────────

function main(): void {
  const [,, repoRoot, outputName = 'docker-compose.yml', hostRepoRoot] = process.argv;
  if (!repoRoot) {
    process.stderr.write('Usage: generate-compose.ts <repo_root> [output-filename] [host-repo-root]\n');
    process.exit(1);
  }

  const outputPath = path.join(repoRoot, outputName);
  const env = loadEnv(path.join(repoRoot, '.env.shared'));
  const enabled = findEnabledServices(repoRoot, env);

  if (!enabled.length) {
    process.stderr.write('No services enabled — set EXIST_IS_*=true in .env.shared\n');
    process.exit(0);
  }

  process.stderr.write(`Enabled (${enabled.length}): ${enabled.join(', ')}\n`);

  const networkExternal = (env['EXIST_NETWORK_EXTERNAL'] ?? 'false').toLowerCase() === 'true';
  const merged = merge(repoRoot, enabled, networkExternal);

  if (hostRepoRoot && !env['EXIST_NFS_SERVER_ADDRESS']?.trim()) {
    convertNfsVolumes(merged, repoRoot, hostRepoRoot);
  }

  mergeEnv(repoRoot, enabled);

  if (fs.existsSync(outputPath)) {
    const now = new Date();
    const stamp = now.toISOString().slice(0, 19).replace('T', '_').replace(/:/g, '-');
    const backup = path.join(repoRoot, `docker-compose-${stamp}.yml`);
    fs.renameSync(outputPath, backup);
    process.stderr.write(`Archived: ${backup}\n`);
  }

  const content = '# Generated by existential.sh — do not edit manually\n' +
    yaml.dump(merged, { noRefs: true, sortKeys: false });
  fs.writeFileSync(outputPath, content);
  process.stderr.write(`Written: ${outputPath}\n`);
}

main();
