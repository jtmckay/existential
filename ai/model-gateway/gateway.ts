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
//   GET  /health      200, for the healthcheck
//
// It reads nothing of the host's: the fleet lib is the workspace's (.decree/lib, read-only),
// and the offers are the controller's Loki.
import http from 'node:http';
import https from 'node:https';
import { readFileSync } from 'node:fs';
import { execFile, spawn } from 'node:child_process';

const SECRET = process.env.EXIST_FLEET_SECRET ?? '';
const LIB = process.env.FLEET_LIB ?? '/fleet/fleet.sh';
const PORT = Number(process.env.PORT ?? 4400);
const SERVICES = new Set(['llm', 'strata']);   // the offers that serve /v1

type Offer = { host: string; service: string; models?: { id: string }[] };

function offers(): Promise<Offer[]> {
  return new Promise(resolve => {
    execFile('bash', ['-c', 'source "$1"; fleet_offers', '_', LIB], { timeout: 20_000 }, (err, out) => {
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
    const p = spawn('bash', ['-c', 'source "$1"; fleet_use "$2" || exit $?; echo "$FLEET_URL"; read -r _; fleet_done "$2"', '_', LIB, service],
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
  const lib = readFileSync(LIB, 'utf8').split('\n').filter(l => !l.startsWith('#!')).map(l => (l ? `    ${l}` : l)).join('\n');
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

    EXIST_CONTROLLER=<the controller's address>
    EXIST_FLEET_SECRET=<the fleet's secret>

Installed, and updated, from the project's root:

    set -a; . .decree/.env; set +a; curl -fsSL -H "Authorization: Bearer $EXIST_FLEET_SECRET" "http://$EXIST_CONTROLLER:4400/plugins/fleet_gpu.md" | decree install -

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
    req.on('data', (d: Buffer) => parts.push(d)).on('end', () => resolve(Buffer.concat(parts))).on('error', reject);
  });
}

http.createServer(async (req, res) => {
  const path = (req.url ?? '/').split('?')[0];
  if (path === '/health') return send(res, 200, { ok: true });
  if (!SECRET) return fail(res, 503, 'no EXIST_FLEET_SECRET: this host is not in a fleet');
  if (req.headers.authorization !== `Bearer ${SECRET}`) return fail(res, 401, 'the key is the fleet secret (EXIST_FLEET_SECRET)');
  if (req.method === 'GET' && path === '/plugins/fleet_gpu.md') {
    try { res.writeHead(200, { 'content-type': 'text/markdown' }); return res.end(fleetGpu()); }
    catch { return fail(res, 503, `no fleet lib at ${LIB} yet: ./existential.sh installs it with the model plugin`); }
  }
  if (!path.startsWith('/v1/')) return fail(res, 404, 'not found: the API is under /v1');

  const all = await offers();
  if (req.method === 'GET' && path === '/v1/models') {
    const ids = [...new Set(all.flatMap(o => (o.models ?? []).map(m => m.id)))];
    return send(res, 200, { object: 'list', data: ids.map(id => ({ id, object: 'model', owned_by: 'fleet' })) });
  }

  const raw = await body(req);
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
}).listen(PORT, () => console.log(`model-gateway: /v1 on :${PORT}, leasing through ${LIB}`));
