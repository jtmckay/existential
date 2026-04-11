const express = require('express');
const rateLimit = require('express-rate-limit');
const yaml = require('js-yaml');
const crypto = require('crypto');
const fs = require('fs/promises');
const fsSync = require('fs');
const path = require('path');

const PORT = parseInt(process.env.DECREE_WEBHOOK_PORT || '8801', 10);
const INBOX = path.resolve(process.env.DECREE_WEBHOOK_INBOX || '/inbox');
const MAX_BODY = process.env.DECREE_WEBHOOK_MAX_BODY || '256kb';
const CONFIG_PATH = process.env.DECREE_WEBHOOK_CONFIG || '/app/config.yml';
const RATE_LIMIT_WINDOW_MS = parseInt(process.env.DECREE_WEBHOOK_RATE_WINDOW_MS || '60000', 10);
const RATE_LIMIT_MAX = parseInt(process.env.DECREE_WEBHOOK_RATE_MAX || '60', 10);
const RATE_LIMIT_FAIL_MAX = parseInt(process.env.DECREE_WEBHOOK_RATE_FAIL_MAX || '10', 10);

const PATH_RE = /^\/[A-Za-z0-9._\-/{}]+$/;
const PARAM_NAME_RE = /^\w+$/;
const DEFAULT_PARAM_RE = /^[A-Za-z0-9_\-!]+$/;
const MAX_PARAM_LEN = 200;

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, ...extra, ts: new Date().toISOString() }));
}

function substituteParams(value, params) {
  if (typeof value === 'string') {
    return value.replace(/\{\{(\w+)\}\}/g, (_, p) => params[p] ?? `{{${p}}}`);
  }
  if (Array.isArray(value)) {
    return value.map(v => substituteParams(v, params));
  }
  if (value !== null && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = substituteParams(v, params);
    return out;
  }
  return value;
}

function validateSecret(secret, label) {
  if (!secret || typeof secret !== 'string' || secret.length < 16) {
    throw new Error(`${label}: secret missing or too short (min 16 chars)`);
  }
}

function loadConfig(file) {
  const raw = fsSync.readFileSync(file, 'utf8');
  const parsed = yaml.load(raw);
  if (!parsed || !Array.isArray(parsed.endpoints) || parsed.endpoints.length === 0) {
    throw new Error('config.yml must contain a non-empty endpoints[] array');
  }
  const globalSecret = parsed.secret || null;
  const seen = new Set();
  const endpoints = [];
  for (const ep of parsed.endpoints) {
    if (!ep || typeof ep.path !== 'string' || !PATH_RE.test(ep.path) || ep.path.includes('..')) {
      throw new Error(`invalid endpoint path: ${JSON.stringify(ep && ep.path)}`);
    }
    if (seen.has(ep.path)) throw new Error(`duplicate endpoint path: ${ep.path}`);
    seen.add(ep.path);
    if (!ep.frontmatter || typeof ep.frontmatter !== 'object' || Array.isArray(ep.frontmatter)) {
      throw new Error(`endpoint ${ep.path} missing frontmatter object`);
    }
    const secret = ep.secret || globalSecret;
    validateSecret(secret, ep.path);

    // Extract param names from {name} placeholders in path
    const paramNames = [...ep.path.matchAll(/\{(\w+)\}/g)].map(m => m[1]);

    // Compile optional per-param validation patterns from config
    const paramPatterns = {};
    if (ep.params != null) {
      if (typeof ep.params !== 'object' || Array.isArray(ep.params)) {
        throw new Error(`endpoint ${ep.path}: params must be a mapping`);
      }
      for (const [name, pattern] of Object.entries(ep.params)) {
        if (!PARAM_NAME_RE.test(name)) {
          throw new Error(`endpoint ${ep.path}: invalid param name "${name}"`);
        }
        if (!paramNames.includes(name)) {
          throw new Error(`endpoint ${ep.path}: params.${name} not present in path`);
        }
        try {
          paramPatterns[name] = new RegExp(`^(?:${pattern})$`);
        } catch {
          throw new Error(`endpoint ${ep.path}: params.${name} has invalid regex`);
        }
      }
    }

    // Convert {name} → :name for Express route registration
    const expressPath = ep.path.replace(/\{(\w+)\}/g, ':$1');

    endpoints.push({ ...ep, secret, paramNames, paramPatterns, expressPath });
  }
  return endpoints;
}

function makeAuth(secret) {
  const secretBuf = Buffer.from(secret, 'utf8');
  return function authMiddleware(req, res, next) {
    const header = req.get('authorization') || '';
    const m = /^Bearer\s+(.+)$/i.exec(header);
    if (!m) return res.status(401).json({ error: 'unauthorized' });
    const token = Buffer.from(m[1], 'utf8');
    if (token.length !== secretBuf.length || !crypto.timingSafeEqual(token, secretBuf)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    return next();
  };
}

function makeHandler(endpoint) {
  return async function handler(req, res) {
    const body = typeof req.body === 'string' ? req.body : '';
    if (!body.trim()) return res.status(400).json({ error: 'empty body' });

    // Validate route params against strict allowlist, then per-param pattern if defined
    const params = {};
    for (const name of endpoint.paramNames) {
      const raw = req.params[name];
      if (!raw) return res.status(400).json({ error: `missing param: ${name}` });
      if (raw.length > MAX_PARAM_LEN) return res.status(400).json({ error: `param too long: ${name}` });
      if (!DEFAULT_PARAM_RE.test(raw)) return res.status(400).json({ error: `invalid param: ${name}` });
      const pattern = endpoint.paramPatterns[name];
      if (pattern && !pattern.test(raw)) return res.status(400).json({ error: `invalid param: ${name}` });
      params[name] = raw;
    }

    // Object-level substitution — yaml.dump() handles all quoting, no string interpolation
    const fm = substituteParams(endpoint.frontmatter, params);
    const fmYaml = yaml.dump(fm, { flowLevel: 1, lineWidth: 1000 });
    const content = `---\n${fmYaml}---\n\n${body}${body.endsWith('\n') ? '' : '\n'}`;

    const filename = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}.md`;
    const full = path.resolve(INBOX, filename);
    if (!full.startsWith(INBOX + path.sep)) {
      return res.status(500).json({ error: 'path resolution failed' });
    }

    try {
      await fs.writeFile(full, content, { mode: 0o640, flag: 'wx' });
    } catch (err) {
      log('error', 'write_failed', { path: endpoint.path, code: err.code });
      return res.status(500).json({ error: 'write failed' });
    }

    log('info', 'enqueued', { path: endpoint.path, file: filename, bytes: Buffer.byteLength(content) });
    return res.status(201).json({ file: filename, path: endpoint.path });
  };
}

function main() {
  let endpoints;
  try {
    endpoints = loadConfig(CONFIG_PATH);
  } catch (err) {
    console.error(JSON.stringify({ level: 'fatal', msg: 'config load failed', error: err.message }));
    process.exit(1);
  }

  try {
    fsSync.accessSync(INBOX, fsSync.constants.W_OK);
  } catch {
    console.error(JSON.stringify({ level: 'fatal', msg: 'inbox not writable', inbox: INBOX }));
    process.exit(1);
  }

  const app = express();
  app.disable('x-powered-by');

  app.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

  app.use(rateLimit({
    windowMs: RATE_LIMIT_WINDOW_MS,
    max: RATE_LIMIT_MAX,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'too many requests' },
  }));

  // Stricter limit on failed requests only — does not penalise successful callers
  app.use(rateLimit({
    windowMs: RATE_LIMIT_WINDOW_MS,
    max: RATE_LIMIT_FAIL_MAX,
    skipSuccessfulRequests: true,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'too many requests' },
  }));

  app.use(express.text({ type: '*/*', limit: MAX_BODY }));

  app.use((err, _req, res, next) => {
    if (err && err.type === 'entity.too.large') {
      return res.status(413).json({ error: 'body too large' });
    }
    return next(err);
  });

  for (const ep of endpoints) {
    app.post(ep.expressPath, makeAuth(ep.secret), makeHandler(ep));
    log('info', 'route_registered', { path: ep.path, expressPath: ep.expressPath });
  }

  app.use((_req, res) => res.status(404).json({ error: 'not found' }));

  app.use((err, _req, res, _next) => {
    log('error', 'unhandled', { error: err && err.message });
    res.status(500).json({ error: 'internal error' });
  });

  app.listen(PORT, () => log('info', 'listening', { port: PORT, inbox: INBOX, endpoints: endpoints.length }));

  let restarting = false;
  const watcher = fsSync.watch(CONFIG_PATH, () => {
    if (restarting) return;
    restarting = true;
    log('info', 'config_changed', { path: CONFIG_PATH, msg: 'restarting to reload config' });
    setTimeout(() => process.exit(0), 300);
  });
  watcher.on('error', (err) => log('warn', 'config_watch_error', { error: err.message }));
}

main();
