#!/usr/bin/env tsx
/**
 * validate-conventions.ts — verify slugs are wired consistently across
 * service compose files, piHole, Caddy, and dashy.
 *
 * Conventions checked:
 *   1. Every container_name is lowercase-hyphenated only.
 *   2. Every container_name starts with its folder's slug.
 *   3. Every piHole record has a matching Caddy reverse_proxy block.
 *   4. Every piHole record has LOCAL active line + PEER commented line.
 *   5. Every Caddy block has a matching piHole record.
 *   6. Every dashy item points at a slug that has a piHole record.
 *   7. Every key in a service's .env.exist starts with <SLUG>_.
 *   8. Every key in .env.exist.shared starts with EXIST_, no legacy prefixes.
 *   9. Every NFS-declared volume in the master docker-compose.yml is fully configured.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PIHOLE   = path.join(REPO_ROOT, 'hosting/pihole/docker-compose.exist.yml');
const CADDY    = path.join(REPO_ROOT, 'hosting/caddy/Caddyfile.exist.Caddyfile');
const DASHY    = path.join(REPO_ROOT, 'services/dashy/dashy-conf.exist.yml');
const ENV_SHARED  = path.join(REPO_ROOT, '.env.exist.shared');
const MASTER_COMPOSE = path.join(REPO_ROOT, 'docker-compose.yml');

const CATEGORY_DIRS = ['ai', 'services', 'hosting', 'nas'];

const CONTAINER_NAME_RE  = /^\s*container_name:\s*([\w-]+)\s*$/;
const PORT_LINE_RE       = /^\s*-\s*"?(?:\$\{[^}]+\}|\d+):(\d+)(?:\/(?:tcp|udp))?"?\s*(?:#.*)?$/;
const CADDY_HEADER_RE    = /^([\w.-]+)\.internal\s*\{/;
const CADDY_PROXY_RE     = /^\s*reverse_proxy\s+(?:https?:\/\/)?([\w-]+):(\d+|\{[^}]+\})/;
const PIHOLE_RECORD_RE   = /^\s*(?<comment>#\s*)?\$\{(?<var>EXIST_(?:LOCAL|PEER)_HOST_IP)\}\s+(?<slug>[\w-]+)\.internal\s*$/;
const DASHY_URL_RE       = /^\s*url:\s*https?:\/\/([\w-]+)\.internal\/?\s*$/;
const ENV_KEY_LINE_RE    = /^([A-Z_][A-Z0-9_]*)=/;

// ── Types ──────────────────────────────────────────────────────────────────────

interface ServiceDecl {
  slug: string;
  file: string;
  line: number;
  folderSlug: string;
  ports: number[];
}

interface PiHoleRecord {
  slug: string;
  line: number;
  hasLocal: boolean;
  hasPeerCommented: boolean;
}

interface CaddyBlock {
  slug: string;
  backendContainer: string;
  backendPort: string;
  line: number;
}

interface DashyItem {
  slug: string;
  line: number;
}

// ── Parsers ────────────────────────────────────────────────────────────────────

function parseServiceComposes(): Map<string, ServiceDecl> {
  const services = new Map<string, ServiceDecl>();

  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;

    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const composePath = path.join(catPath, entry.name, 'docker-compose.exist.yml');
      if (!fs.existsSync(composePath)) continue;

      const folderSlug = entry.name;
      let currentDecl: ServiceDecl | null = null;
      const lines = fs.readFileSync(composePath, 'utf8').split('\n');

      for (let lineno = 0; lineno < lines.length; lineno++) {
        const raw = lines[lineno];
        const nm = CONTAINER_NAME_RE.exec(raw);
        if (nm) {
          currentDecl = {
            slug: nm[1],
            file: composePath,
            line: lineno + 1,
            folderSlug,
            ports: [],
          };
          if (!services.has(nm[1])) services.set(nm[1], currentDecl);
          continue;
        }
        if (!currentDecl) continue;
        const pm = PORT_LINE_RE.exec(raw);
        if (pm) currentDecl.ports.push(parseInt(pm[1], 10));
      }
    }
  }

  return services;
}

function parsePiHole(): Map<string, PiHoleRecord> {
  const records = new Map<string, PiHoleRecord>();
  if (!fs.existsSync(PIHOLE)) return records;

  const lines = fs.readFileSync(PIHOLE, 'utf8').split('\n');
  for (let lineno = 0; lineno < lines.length; lineno++) {
    const m = PIHOLE_RECORD_RE.exec(lines[lineno]);
    if (!m?.groups) continue;
    const { comment, var: varName, slug } = m.groups;
    const commented = comment !== undefined;

    if (!records.has(slug)) records.set(slug, { slug, line: lineno + 1, hasLocal: false, hasPeerCommented: false });
    const rec = records.get(slug)!;
    if (varName === 'EXIST_LOCAL_HOST_IP' && !commented) rec.hasLocal = true;
    if (varName === 'EXIST_PEER_HOST_IP'  && commented)  rec.hasPeerCommented = true;
  }

  return records;
}

function parseCaddy(): Map<string, CaddyBlock> {
  const blocks = new Map<string, CaddyBlock>();
  if (!fs.existsSync(CADDY)) return blocks;

  let currentSlug: string | null = null;
  let currentLine = 0;
  const lines = fs.readFileSync(CADDY, 'utf8').split('\n');

  for (let lineno = 0; lineno < lines.length; lineno++) {
    const raw = lines[lineno];
    const hm = CADDY_HEADER_RE.exec(raw);
    if (hm) { currentSlug = hm[1]; currentLine = lineno + 1; continue; }
    if (currentSlug) {
      const pm = CADDY_PROXY_RE.exec(raw);
      if (pm) {
        blocks.set(currentSlug, {
          slug: currentSlug,
          backendContainer: pm[1],
          backendPort: pm[2],
          line: currentLine,
        });
        currentSlug = null;
      }
    }
  }

  return blocks;
}

function parseDashy(): DashyItem[] {
  const items: DashyItem[] = [];
  if (!fs.existsSync(DASHY)) return items;

  const lines = fs.readFileSync(DASHY, 'utf8').split('\n');
  for (let lineno = 0; lineno < lines.length; lineno++) {
    const raw = lines[lineno];
    if (raw.trimStart().startsWith('#')) continue;
    const m = DASHY_URL_RE.exec(raw);
    if (m) items.push({ slug: m[1], line: lineno + 1 });
  }

  return items;
}

// ── Env checks ─────────────────────────────────────────────────────────────────

function envFileKeys(filePath: string): Array<[number, string]> {
  if (!fs.existsSync(filePath)) return [];
  const out: Array<[number, string]> = [];
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (!raw.trim() || raw.trimStart().startsWith('#')) continue;
    const m = ENV_KEY_LINE_RE.exec(raw);
    if (m) out.push([i + 1, m[1]]);
  }
  return out;
}

function checkServiceEnvPrefixes(): string[] {
  const errors: string[] = [];
  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;

    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const envFile = path.join(catPath, entry.name, '.env.exist');
      if (!fs.existsSync(envFile)) continue;

      const head = fs.readFileSync(envFile, 'utf8').split('\n').slice(0, 5).join('\n');
      if (head.includes('convention-exempt: upstream-env')) continue;

      const slug = entry.name;
      const prefix = slug.replace(/-/g, '_').toUpperCase() + '_';
      const rel = path.relative(REPO_ROOT, envFile);

      for (const [lineno, key] of envFileKeys(envFile)) {
        if (!key.startsWith(prefix)) {
          errors.push(
            `${rel}:${lineno}: key '${key}' must start with '${prefix}' ` +
            `(map image-required names like MYSQL_USER in docker-compose.exist.yml instead)`,
          );
        }
      }
    }
  }
  return errors;
}

function checkTopLevelEnvKeys(): string[] {
  const errors: string[] = [];
  for (const [lineno, key] of envFileKeys(ENV_SHARED)) {
    if (!key.startsWith('EXIST_')) {
      errors.push(`.env.exist.shared:${lineno}: key '${key}' must start with 'EXIST_'`);
      continue;
    }
    if (key.startsWith('EXIST_DEFAULT_')) {
      const newKey = 'EXIST_' + key.slice('EXIST_DEFAULT_'.length);
      errors.push(`.env.exist.shared:${lineno}: key '${key}' uses the legacy DEFAULT prefix — rename to '${newKey}'`);
    } else if (key.startsWith('EXIST_ENABLE_')) {
      const newKey = 'EXIST_IS_' + key.slice('EXIST_ENABLE_'.length);
      errors.push(`.env.exist.shared:${lineno}: key '${key}' uses the legacy ENABLE prefix — rename to '${newKey}'`);
    }
  }
  return errors;
}

function checkNfsVolumes(): string[] {
  const errors: string[] = [];
  if (!fs.existsSync(MASTER_COMPOSE)) return errors;

  let data: Record<string, unknown>;
  try {
    data = (yaml.load(fs.readFileSync(MASTER_COMPOSE, 'utf8')) ?? {}) as Record<string, unknown>;
  } catch (e) {
    return [`docker-compose.yml: failed to parse — ${e}`];
  }

  const volumes = (data['volumes'] ?? {}) as Record<string, unknown>;
  for (const [name, spec] of Object.entries(volumes)) {
    if (typeof spec !== 'object' || spec === null) continue;
    const opts = (spec as Record<string, unknown>)['driver_opts'];
    if (typeof opts !== 'object' || opts === null) continue;
    const o = opts as Record<string, unknown>;
    if (String(o['type'] ?? '').toLowerCase() !== 'nfs') continue;

    if (!String(o['o'] ?? '').includes('addr=')) {
      errors.push(`docker-compose.yml: volume '${name}' has type: nfs but \`o:\` is missing \`addr=…\` — would fall back to a local volume`);
    }
    if (!o['device']) {
      errors.push(`docker-compose.yml: volume '${name}' has type: nfs but \`device:\` is empty`);
    }
  }
  return errors;
}

// ── Main ──────────────────────────────────────────────────────────────────────

function main(): number {
  const services  = parseServiceComposes();
  const pihole    = parsePiHole();
  const caddy     = parseCaddy();
  const dashyItems = parseDashy();

  const errors: string[] = [];
  const warnings: string[] = [];

  // (1) container_name format — lowercase-hyphenated only
  const badNameRe = /[A-Z_]/;
  for (const [slug, decl] of services) {
    if (badNameRe.test(slug)) {
      errors.push(
        `${path.relative(REPO_ROOT, decl.file)}:${decl.line}: ` +
        `container_name '${slug}' is not lowercase-hyphenated`,
      );
    }
  }

  // (2) container_name prefixed with folder slug
  for (const [slug, decl] of services) {
    if (!decl.folderSlug) continue;
    if (slug === decl.folderSlug) continue;
    if (!slug.startsWith(`${decl.folderSlug}-`)) {
      errors.push(
        `${path.relative(REPO_ROOT, decl.file)}:${decl.line}: ` +
        `container_name '${slug}' must start with '${decl.folderSlug}-' ` +
        `(or equal '${decl.folderSlug}') so it's obvious which service it belongs to`,
      );
    }
  }

  // (3)+(4) piHole records have both LOCAL and PEER lines
  for (const [, rec] of pihole) {
    if (!rec.hasLocal) {
      errors.push(
        `hosting/pihole/docker-compose.exist.yml:${rec.line}: ` +
        `slug '${rec.slug}' has no active LOCAL_HOST_IP record`,
      );
    }
    if (!rec.hasPeerCommented) {
      errors.push(
        `hosting/pihole/docker-compose.exist.yml:${rec.line}: ` +
        `slug '${rec.slug}' has no commented PEER_HOST_IP fallback line`,
      );
    }
  }

  // (5) Caddy and piHole are mirror sets
  const piholeSlugSet = new Set(pihole.keys());
  const caddySlugSet  = new Set(caddy.keys());

  for (const slug of piholeSlugSet) {
    if (!caddySlugSet.has(slug)) {
      errors.push(
        `hosting/pihole/docker-compose.exist.yml: ` +
        `slug '${slug}.internal' has a DNS record but no Caddy reverse_proxy block`,
      );
    }
  }
  for (const slug of caddySlugSet) {
    if (!piholeSlugSet.has(slug)) {
      errors.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile: ` +
        `slug '${slug}.internal' has a Caddy block but no piHole record`,
      );
    }
  }

  // (6) Caddy backend matches an actual container
  const containerPorts = new Map<string, Set<number>>();
  for (const [slug, decl] of services) {
    containerPorts.set(slug, new Set(decl.ports));
  }

  for (const [slug, block] of caddy) {
    const decl = services.get(block.backendContainer);
    if (!decl) {
      errors.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile:${block.line}: ` +
        `'${slug}.internal' proxies to '${block.backendContainer}' — ` +
        `no service compose declares that container_name`,
      );
      continue;
    }
    if (block.backendPort.startsWith('{')) continue;
    const portInt = parseInt(block.backendPort, 10);
    if (isNaN(portInt)) continue;
    const ports = containerPorts.get(block.backendContainer) ?? new Set();
    if (ports.size > 0 && !ports.has(portInt)) {
      warnings.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile:${block.line}: ` +
        `'${slug}.internal' → ${block.backendContainer}:${portInt}, but ` +
        `the compose file only publishes [${[...ports].sort().join(', ')}] ` +
        `(${path.relative(REPO_ROOT, decl.file)}:${decl.line}). ` +
        `OK if the container exposes more than it publishes.`,
      );
    }
  }

  // (7) Dashy items point at known slugs
  for (const item of dashyItems) {
    if (!piholeSlugSet.has(item.slug)) {
      errors.push(
        `services/dashy/dashy-conf.exist.yml:${item.line}: ` +
        `item references '${item.slug}.internal' but no piHole record exists`,
      );
    }
  }

  // (8) Service env var keys start with <SLUG>_
  errors.push(...checkServiceEnvPrefixes());

  // (9) .env.exist.shared keys start with EXIST_, no legacy prefixes
  errors.push(...checkTopLevelEnvKeys());

  // (10) NFS-declared volumes in master compose are fully configured
  errors.push(...checkNfsVolumes());

  // (11) Quest files: e2e: false must have e2e_skip explaining why
  const questsDir = path.join(REPO_ROOT, 'src/quests');
  if (fs.existsSync(questsDir)) {
    for (const f of fs.readdirSync(questsDir).filter(n => /^\d.*\.yml$/.test(n))) {
      const content = fs.readFileSync(path.join(questsDir, f), 'utf8');
      const lines = content.split('\n');
      const hasE2eFalse = lines.some(l => /^e2e:\s*false/.test(l));
      const hasE2eSkip  = lines.some(l => /^e2e_skip:\s*\S/.test(l));
      if (hasE2eFalse && !hasE2eSkip) {
        errors.push(
          `src/quests/${f}: has 'e2e: false' but no 'e2e_skip:' explanation — add one`,
        );
      }
    }
  }

  // ── Report ──────────────────────────────────────────────────────────────────
  console.log(`Services declared:    ${services.size}`);
  console.log(`piHole records:       ${pihole.size}`);
  console.log(`Caddy blocks:         ${caddy.size}`);
  console.log(`Dashy items:          ${dashyItems.length}`);
  console.log();

  if (warnings.length) {
    console.log(`Warnings (${warnings.length}):`);
    for (const w of warnings) console.log(`  - ${w}`);
    console.log();
  }

  if (errors.length) {
    console.log(`Errors (${errors.length}):`);
    for (const e of errors) console.log(`  ✗ ${e}`);
    console.log();
    console.log('Validation FAILED. Fix the above to keep conventions in sync.');
    return 1;
  }

  console.log('Validation passed.');
  return 0;
}

process.exit(main());
