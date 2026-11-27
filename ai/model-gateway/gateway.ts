// model-gateway — an OpenAI-compatible /v1 in front of the fleet's GPU hosts.
//
// Point any client at it (opencode, pi, a decree script, anything with a base URL and a key)
// with the fleet secret as its key. A call names a model; the gateway finds the host whose
// offer lists it (fleet_offers, the controller's Loki), holds that host's lease for the call
// (fleet_use / fleet_done, the same lib decree scripts use: calls share one lease, given back
// FLEET_IDLE seconds after the last), and streams the host's answer back.
//
//   GET  /v1/models   every model a GPU host offers now
//   POST /v1/...      to the host serving body.model (blank: the first one offered)
//   GET  /plugins/fleet_gpu.md   the fleet lib as a decree plugin, for a project of your own
//   *    /loki/api/v1/{push,query_range,labels,status/buildinfo}   this host's Loki, for the
//                     other hosts, as https://model-gateway.<domain> through Caddy (Loki has no login)
//   GET  /health, /ready   200, for the healthcheck; /ready is Loki's
//
// Everything else takes the fleet secret as its key. It reads nothing of the host's, and
// nothing the workspace can change: the fleet lib is the repo's own plugin file
// (automation/plugins/fleet.md, read-only), and the offers are this host's Loki.
import http from 'node:http';
import https from 'node:https';
import { readFileSync } from 'node:fs';
import { execFile, spawn } from 'node:child_process';
import { createHash, timingSafeEqual } from 'node:crypto';

const SECRET = process.env.EXIST_FLEET_SECRET ?? '';
const LIB = process.env.FLEET_LIB ?? '/fleet/fleet.md';
const LOKI = (process.env.FLEET_LOKI_UPSTREAM ?? 'http://loki:3100').replace(/\/$/, '');
const PORT = Number(process.env.PORT ?? 4400);
const MAX_BODY = 64 * 1024 * 1024;              // a chat with images in it, never more
const SERVICES = new Set(['llm', 'strata']);   // the offers that serve /v1
const LOKI_PATHS = new Set(['/loki/api/v1/push', '/loki/api/v1/query_range', '/loki/api/v1/labels', '/loki/api/v1/status/buildinfo']);

// The fleet lib's source: fleet.sh as the plugin file holds it (x-exist-lib, indented four),
// or a plain fleet.sh. Read on every call, so a pulled checkout needs no restart.
function libSource(): string {
  const text = readFileSync(LIB, 'utf8');
  if (!LIB.endsWith('.md')) return text;
  const lines = text.split('\n');
  const start = lines.findIndex(l => l === '  fleet.sh: |');
  if (start < 0) throw new Error(`no fleet.sh in ${LIB}`);
  const out: string[] = [];
  for (const l of lines.slice(start + 1)) {
    if (l !== '' && !l.startsWith('    ')) break;
    out.push(l.slice(4));
  }
  return out.join('\n');
}

// The key, compared in constant time.
const digest = (s: string) => createHash('sha256').update(s).digest();
const WANT = digest(`Bearer ${SECRET}`);
const authorized = (req: http.IncomingMessage) => timingSafeEqual(digest(String(req.headers.authorization ?? '')), WANT);

type Offer = { host: string; service: string; models?: { id: string }[] };

function offers(): Promise<Offer[]> {
  return new Promise(resolve => {
    let src: string;
    try { src = libSource(); } catch { return resolve([]); }
    execFile('bash', ['-c', 'eval "$1"; fleet_offers', '_', src], { timeout: 20_000 }, (err, out) => {
      if (err) return resolve([]);
      resolve(out.split('\n').flatMap(l => { try { return [JSON.parse(l) as Offer]; } catch { return []; } })
        .filter(o => SERVICES.has(o.service)));
    });
  });
}

// One call's hold on a lease: a bash process inside fleet_use until its stdin closes, so the
// keeper counts the call in flight while it lives (fleet.sh's own rule).
function lease(service: string): Promise<{ url: string; done: () => void }> {
  return new Promise((resolve, reject) => {
    let src: string;
    try { src = libSource(); } catch (e) { return reject(e); }
    const p = spawn('bash', ['-c', 'eval "$1"; fleet_use "$2" || exit $?; echo "$FLEET_URL"; read -r _; fleet_done "$2"', '_', src, service],
      { stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '', held = false;
    p.stdout.on('data', (d: Buffer) => {
      out += d.toString();
      const i = out.indexOf('\n');
      if (i < 0 || held) return;
      held = true;
      let ended = false;
      resolve({ url: out.slice(0, i).trim(), done: () => { if (!ended) { ended = true; p.stdin.end('\n'); } } });
    });
    p.on('exit', code => { if (!held) reject(new Error(code === 3 ? `no host offers ${service}` : `${service}'s host would not lease it`)); });
  });
}

// fleet_gpu.md: the fleet lib this gateway leases through, as a decree plugin file. Data to
// serve, never run here: no #! line, so decree check takes the script as data.
function fleetGpu(): string {
  const lib = libSource().split('\n').filter(l => !l.startsWith('#!')).map(l => (l ? `    ${l}` : l)).join('\n');
  return `---
name: fleet_gpu
scripts:
  requirements: |
    # kind    name
    command   curl
    command   jq
  fleet.sh: |
${lib.replace(/\s+$/, '')}
---
# fleet_gpu

The GPUs of an existential fleet, for a decree project of your own: llama.cpp (\`llm\`), Strata
(\`strata\`), ComfyUI (\`comfy\`) and TTS (\`tts\`), each on whichever host offers it now, found by
asking the fleet's controller, and used under that host's lease.

In \`.decree/.env\`:

    EXIST_CONTROLLER=<the controller's domain>
    EXIST_FLEET_SECRET=<the fleet's secret>

Installed, and updated, from the project's root:

    set -a; . .decree/.env; set +a; curl -fsSL -H "Authorization: Bearer $EXIST_FLEET_SECRET" "https://model-gateway.$EXIST_CONTROLLER/plugins/fleet_gpu.md" | decree install -

In a script:

    source .decree/machines/fleet_gpu/scripts/fleet.sh
    fleet_use comfy || exit 1        # FLEET_URL is ComfyUI's address, under its lease
    curl -fsS "\${FLEET_URL}/prompt" -d @workflow.json
    fleet_done comfy

The lease is taken by the first \`fleet_use\`, shared by every call after it, renewed while they
come, and given back 5 seconds after the last \`fleet_done\` (ComfyUI: once its queue is empty).
\`fleet_use\` returns 3 when no host offers the service, 1 when none would lease it.
\`fleet_offers\` lists what every host offers. Needs curl and jq.
`;
}

function send(res: http.ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}
const fail = (res: http.ServerResponse, status: number, message: string) => send(res, status, { error: { message } });

function body(req: http.IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const parts: Buffer[] = [];
    let size = 0;
    req.on('data', (d: Buffer) => {
      size += d.length;
      if (size > MAX_BODY) { req.removeAllListeners('data'); req.resume(); return reject(new Error('too large')); }
      parts.push(d);
    }).on('end', () => resolve(Buffer.concat(parts))).on('error', reject);
  });
}

// This host's Loki, for the hosts on your own network: the request as it came, minus its key.
function toLoki(req: http.IncomingMessage, res: http.ServerResponse, url: string): void {
  const headers = { ...req.headers };
  delete headers.authorization; delete headers.host;
  const up = http.request(`${LOKI}${url}`, { method: req.method, headers }, upRes => {
    res.writeHead(upRes.statusCode ?? 502, upRes.headers);
    upRes.pipe(res);
  });
  up.on('error', e => { if (!res.headersSent) fail(res, 502, `loki: ${e.message}`); else res.end(); });
  let size = 0;
  req.on('data', (d: Buffer) => { size += d.length; if (size > MAX_BODY) { up.destroy(); req.destroy(); } });
  req.pipe(up);
}

http.createServer(async (req, res) => {
  const path = (req.url ?? '/').split('?')[0];
  if (path === '/health') return send(res, 200, { ok: true });
  if (path === '/ready' && req.method === 'GET') return toLoki(req, res, '/ready');
  if (!SECRET) return fail(res, 503, 'no EXIST_FLEET_SECRET: this host is not in a fleet');
  if (!authorized(req)) return fail(res, 401, 'the key is the fleet secret (EXIST_FLEET_SECRET)');
  if (LOKI_PATHS.has(path)) return toLoki(req, res, req.url ?? path);
  if (req.method === 'GET' && path === '/plugins/fleet_gpu.md') {
    let md: string;
    try { md = fleetGpu(); } catch { return fail(res, 503, `no fleet lib at ${LIB}`); }
    res.writeHead(200, { 'content-type': 'text/markdown' }); return res.end(md);
  }
  if (!path.startsWith('/v1/')) return fail(res, 404, 'not found: the API is under /v1');

  const all = await offers();
  if (req.method === 'GET' && path === '/v1/models') {
    const ids = [...new Set(all.flatMap(o => (o.models ?? []).map(m => m.id)))];
    return send(res, 200, { object: 'list', data: ids.map(id => ({ id, object: 'model', owned_by: 'fleet' })) });
  }

  let raw: Buffer;
  try { raw = await body(req); } catch { res.setHeader('connection', 'close'); return fail(res, 413, `the body is over ${MAX_BODY / 1024 / 1024} MB`); }
  let model = '';
  try { model = String(JSON.parse(raw.toString() || '{}').model ?? ''); } catch { return fail(res, 400, 'the body is not JSON'); }
  const offer = model ? all.find(o => (o.models ?? []).some(m => m.id === model)) : all.find(o => (o.models ?? []).length);
  if (!offer) return fail(res, 404, model ? `no host offers ${model} now (GET /v1/models lists what they do)` : 'no host offers a model now');

  let held: { url: string; done: () => void };
  try { held = await lease(offer.service); } catch (e) { return fail(res, 503, (e as Error).message); }
  const target = new URL(held.url.replace(/\/$/, '') + path.slice('/v1'.length));
  const up = (target.protocol === 'https:' ? https : http).request(target, {
    method: req.method,
    headers: { 'content-type': req.headers['content-type'] ?? 'application/json', authorization: `Bearer ${SECRET}`, 'content-length': raw.length },
  }, upRes => {
    res.writeHead(upRes.statusCode ?? 502, upRes.headers);
    upRes.pipe(res);
  });
  res.on('close', held.done);
  up.on('error', e => { held.done(); if (!res.headersSent) fail(res, 502, `${offer.host}: ${e.message}`); else res.end(); });
  up.end(raw);
}).listen(PORT, () => console.log(`model-gateway: /v1 and Loki on :${PORT}, leasing through ${LIB}`));
