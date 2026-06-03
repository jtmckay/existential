#!/usr/bin/env tsx
// Generate and import a Lowcoder app with trigger buttons for each decree
// webhook endpoint. App is named "Decree Routines YYYYMMDD_HHMMSS" — each
// run creates a new app, leaving previous ones intact.
//
// Reads:  services/decree/webhook/config.yml  (endpoints + shared secret)
//         services/lowcoder/.env              (LOWCODER_USERNAME, LOWCODER_PASSWORD)
// Writes: a new Lowcoder app via POST /api/v1/applications

import * as fs from "fs";
import * as yaml from "js-yaml";

const REPO = process.env.REPO_DIR ?? "/repo";
const LOWCODER_URL = "http://lowcoder-api-service:8080";

// ── Credentials ───────────────────────────────────────────────────────────────

function readEnvFile(p: string): Record<string, string> {
  try {
    return Object.fromEntries(
      fs.readFileSync(p, "utf-8")
        .split("\n")
        .flatMap((l) => {
          const m = l.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
          return m ? [[m[1], m[2]]] : [];
        })
    );
  } catch {
    return {};
  }
}

const lcEnv = readEnvFile(`${REPO}/services/lowcoder/.env`);
const LC_EMAIL = process.env.LOWCODER_USERNAME ?? lcEnv.LOWCODER_USERNAME ?? "";
const LC_PASSWORD = process.env.LOWCODER_PASSWORD ?? lcEnv.LOWCODER_PASSWORD ?? "";

if (!LC_EMAIL || !LC_PASSWORD) {
  console.error("LOWCODER_USERNAME / LOWCODER_PASSWORD not found in services/lowcoder/.env");
  process.exit(1);
}

// ── Webhook config ────────────────────────────────────────────────────────────

interface WebhookEndpoint {
  path: string;
  secret?: string;
  frontmatter?: Record<string, unknown>;
}

interface WebhookConfig {
  secret?: string;
  endpoints?: WebhookEndpoint[];
}

const webhookConfig = yaml.load(
  fs.readFileSync(`${REPO}/services/decree/webhook/config.yml`, "utf-8")
) as WebhookConfig;

const SHARED_SECRET = webhookConfig.secret ?? "";
// Browser-side URL — resolves via pihole DNS through Caddy (no port needed).
const WEBHOOK_BASE = "https://decree-webhook.internal";

// ── App name ──────────────────────────────────────────────────────────────────

const now = new Date();
const pad = (n: number) => String(n).padStart(2, "0");
const stamp = [
  now.getFullYear(),
  pad(now.getMonth() + 1),
  pad(now.getDate()),
  "_",
  pad(now.getHours()),
  pad(now.getMinutes()),
  pad(now.getSeconds()),
].join("");
const APP_NAME = `Decree Routines ${stamp}`;

// ── DSL builder ───────────────────────────────────────────────────────────────
// Lowcoder grid: 24 columns. Each endpoint becomes a button (static path) or
// a form with a text input (path contains {param} segments).

interface Endpoint {
  path: string;
  routine: string;
  secret: string;
  hasParam: boolean;
  staticPath: string; // {param} segments stripped
}

function resolveEndpoints(): Endpoint[] {
  return (webhookConfig.endpoints ?? []).map((ep) => ({
    path: ep.path,
    routine: String(ep.frontmatter?.routine ?? ep.path),
    secret: ep.secret ?? SHARED_SECRET,
    hasParam: ep.path.includes("{"),
    staticPath: ep.path.replace(/\/\{[^}]+\}.*$/, ""),
  }));
}

function buildDSL(endpoints: Endpoint[]): object {
  const layout: Record<string, object> = {};
  const items: Record<string, object> = {};
  const queries: object[] = [];

  endpoints.forEach((ep, i) => {
    const col = (i % 4) * 6;
    const row = Math.floor(i / 4) * 8;
    const btnId = `btn${i}`;
    const inputId = `input${i}`;
    const qId = `q${i}`;
    const label = ep.hasParam
      ? `${ep.routine} (${ep.path.match(/\{([^}]+)\}/)?.[1] ?? "value"})`
      : ep.routine;

    // REST query for this endpoint
    queries.push({
      id: qId,
      name: qId,
      compType: "restapi",
      comp: {
        url: { value: JSON.stringify(`${WEBHOOK_BASE}${ep.staticPath}`) },
        httpMethod: "POST",
        headers: [
          { key: "Authorization", value: JSON.stringify(`Bearer ${ep.secret}`) },
          { key: "Content-Type",  value: JSON.stringify("application/json") },
        ],
        body: { value: JSON.stringify("{}") },
      },
    });

    if (ep.hasParam) {
      // Input + button pair
      layout[inputId] = { i: inputId, x: col, y: row,     w: 6, h: 5 };
      layout[btnId]   = { i: btnId,   x: col, y: row + 5, w: 6, h: 3 };

      items[inputId] = {
        compType: "input",
        comp: { label: { value: JSON.stringify(label) } },
      };
      items[btnId] = {
        compType: "button",
        comp: {
          text: { value: JSON.stringify("Run") },
          onClick: [{ name: "runQuery", queryName: qId }],
        },
      };
    } else {
      // Button only
      layout[btnId] = { i: btnId, x: col, y: row, w: 6, h: 5 };
      items[btnId] = {
        compType: "button",
        comp: {
          text: { value: JSON.stringify(label) },
          onClick: [{ name: "runQuery", queryName: qId }],
        },
      };
    }
  });

  return { ui: { compType: "page", comp: { layout, items } }, queries };
}

// ── Lowcoder API ──────────────────────────────────────────────────────────────

async function api(
  method: string,
  path: string,
  body?: object,
  token?: string
): Promise<Response> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return fetch(`${LOWCODER_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Connecting to Lowcoder at ${LOWCODER_URL}...`);

  const loginRes = await api("POST", "/api/v1/auth/form/login", {
    loginId: LC_EMAIL,
    password: LC_PASSWORD,
    register: false,
  });

  if (!loginRes.ok) {
    console.error(`Login failed (${loginRes.status}): ${await loginRes.text()}`);
    process.exit(1);
  }

  const { data: loginData } = await loginRes.json() as { data?: { token?: string } };
  const token = loginData?.token;
  if (!token) {
    console.error("No token returned from login. Check credentials.");
    process.exit(1);
  }

  const endpoints = resolveEndpoints();
  console.log(`Building "${APP_NAME}" with ${endpoints.length} endpoint(s)...`);

  const createRes = await api(
    "POST",
    "/api/v1/applications",
    { name: APP_NAME, applicationType: 1, editingApplicationDSL: buildDSL(endpoints) },
    token
  );

  if (!createRes.ok) {
    console.error(`App creation failed (${createRes.status}): ${await createRes.text()}`);
    process.exit(1);
  }

  const { data: createData } = await createRes.json() as {
    data?: { applicationInfoView?: { applicationId?: string } };
  };
  const appId = createData?.applicationInfoView?.applicationId;

  console.log(`\nCreated: ${APP_NAME}`);
  if (appId) console.log(`  https://lowcoder.internal/apps/${appId}/view`);
  console.log(`  Or open Lowcoder and find it in the app list.`);
}

main().catch((err) => { console.error("Error:", err); process.exit(1); });
