// Patch a captured ComfyUI /api/prompt body from a declarative binding file and
// print the finished POST body on stdout (a summary goes to stderr).
//
//   tsx patch.ts workflows/<type>.yml   <<< '{"params":{...},"items":[...]}'
//
// One patcher for every flow: what a workflow exposes lives in its sibling
// <type>.yml, never here. Adding a workflow is adding a .json and a .yml.
//
// Bindings address nodes by their id in `.prompt`, and a missing id or input is a
// hard error — a re-exported workflow renumbers its nodes, and a silent no-op
// just hands back the template's own default image.

import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { load } from "js-yaml";

interface Bind {
  node: string | number;
  input?: string;
  widget?: number;
  default?: unknown;
}

interface ParamSpec {
  type?: "string" | "int" | "float" | "bool" | "image";
  default?: unknown;
  required?: boolean;
  align?: number;
  bind?: Bind[];
  // Where to mirror the seed control widget ("randomize" | "fixed"). Only
  // meaningful on a param whose default is `random`.
  mode_bind?: Bind[];
}

interface Binding {
  workflow: string;
  params?: Record<string, ParamSpec>;
  items?: { max?: number; branches: Record<string, Bind>[] };
}

interface PromptNode {
  inputs: Record<string, unknown>;
  class_type: string;
  _meta?: { title?: string };
}

type Prompt = Record<string, PromptNode>;

interface UiNode {
  id: number | string;
  widgets_values?: unknown[];
}

function die(msg: string): never {
  console.error(`comfy patch: ${msg}`);
  process.exit(1);
}

/** Round to the nearest multiple of `n` — diffusion models reject odd sizes. */
function align(value: number, n: number): number {
  return Math.round(value / n) * n;
}

function randomSeed(): number {
  return Math.floor(Math.random() * 999999999999999) + 1;
}

function coerce(name: string, spec: ParamSpec, raw: unknown): unknown {
  switch (spec.type ?? "string") {
    case "int": {
      const n = Number(raw);
      if (!Number.isFinite(n)) die(`${name}: "${raw}" is not a number`);
      return spec.align ? align(n, spec.align) : Math.round(n);
    }
    case "float": {
      const n = Number(raw);
      if (!Number.isFinite(n)) die(`${name}: "${raw}" is not a number`);
      return n;
    }
    case "bool":
      return raw === true || raw === "true" || raw === "1";
    default:
      return String(raw);
  }
}

/**
 * A ComfyUI image combo value is "subdir/foo.png [input]" — the API takes that
 * whole string, the UI widget takes it split into [name, folder_type].
 */
function splitImage(value: string): [string, string] {
  const m = value.match(/^(.*)\s+\[([a-z]+)\]$/);
  return m ? [m[1], m[2]] : [value, "image"];
}

// --- Inputs -----------------------------------------------------------------

const bindingPath = process.argv[2];
if (!bindingPath) die("usage: patch.ts <binding.yml>  (params JSON on stdin)");

const binding = load(readFileSync(bindingPath, "utf8")) as Binding;
if (!binding?.workflow) die(`${bindingPath}: no "workflow:" key`);

const workflowPath = resolve(dirname(bindingPath), binding.workflow);
const raw = JSON.parse(readFileSync(workflowPath, "utf8"));

// A devtools capture of POST /api/prompt is already the envelope; ComfyUI's
// "Export (API)" gives the bare prompt map, which needs wrapping. The capture
// also carries extra_pnginfo — the UI graph embedded into the saved file so it
// re-opens as a working workflow — which is why binds can name a widget.
const body = raw.prompt
  ? raw
  : { client_id: randomBytes(16).toString("hex"), prompt: raw };
const prompt: Prompt = body.prompt;
const uiNodes: UiNode[] | undefined =
  body.extra_data?.extra_pnginfo?.workflow?.nodes;

const stdin = readFileSync(0, "utf8").trim();
const input = stdin ? JSON.parse(stdin) : {};
const given: Record<string, unknown> = input.params ?? {};
const items: Record<string, unknown>[] = input.items ?? [];

// --- Patching ---------------------------------------------------------------

const applied: string[] = [];

function apply(label: string, bind: Bind, value: unknown): void {
  const id = String(bind.node);

  if (bind.input !== undefined) {
    const node = prompt[id];
    if (!node) die(`${label}: node ${id} is not in this workflow`);
    if (!(bind.input in node.inputs)) {
      die(`${label}: node ${id} (${node.class_type}) has no input "${bind.input}"`);
    }
    node.inputs[bind.input] = value;
  }

  if (bind.widget === undefined || !uiNodes) return;

  const ui = uiNodes.find((n) => String(n.id) === id);
  if (!ui) die(`${label}: node ${id} is not in the embedded UI graph`);
  ui.widgets_values ??= [];
  if (typeof value === "string" && /\s\[[a-z]+\]$/.test(value)) {
    const [name, folder] = splitImage(value);
    ui.widgets_values[bind.widget] = name;
    ui.widgets_values[bind.widget + 1] = folder;
  } else {
    ui.widgets_values[bind.widget] = value;
  }
}

for (const [name, spec] of Object.entries(binding.params ?? {})) {
  let value = given[name];
  let randomized = false;

  if (value === undefined || value === "") {
    if (spec.default === "random") {
      value = randomSeed();
      randomized = true;
    } else if (spec.default !== undefined) {
      value = spec.default;
    } else if (spec.required) {
      die(`${name} is required`);
    } else {
      continue; // Not given, no default: leave the template's own value alone.
    }
  }

  value = coerce(name, spec, value);
  for (const bind of spec.bind ?? []) apply(name, bind, value);
  for (const bind of spec.mode_bind ?? []) {
    apply(name, bind, randomized ? "randomize" : "fixed");
  }
  applied.push(`${name}=${String(value).slice(0, 60)}`);
}

// --- Batch items ------------------------------------------------------------

if (binding.items) {
  const branches = binding.items.branches ?? [];
  const max = binding.items.max ?? branches.length;

  if (items.length === 0) {
    die("this workflow takes a list of items — put a YAML list of {prompt, output} in the message body");
  }
  if (items.length > max) {
    die(`${items.length} items, but this workflow has only ${max} branches`);
  }

  items.forEach((item, i) => {
    const branch = branches[i];
    for (const [field, bind] of Object.entries(branch)) {
      let value = item[field];
      if (value === undefined || value === "") {
        if (bind.default === "random") value = randomSeed();
        else if (bind.default !== undefined) value = bind.default;
        else if (field === "prompt" || field === "output") {
          die(`item ${i + 1} has no "${field}"`);
        } else continue;
      }
      apply(`item ${i + 1} ${field}`, bind, value);
    }
    applied.push(`item ${i + 1}: ${String(item.output)} <- ${String(item.prompt).slice(0, 50)}`);
  });

  // Drop the branches nobody asked for, so they cost no GPU time. Which nodes
  // belong to a branch is derived, not declared: keep only what a surviving
  // terminal node reaches upstream.
  const dropped = new Set(branches.slice(items.length).map((b) => String(b.output.node)));
  if (dropped.size) prune(dropped);
}

function prune(droppedOutputs: Set<string>): void {
  const referenced = new Set<string>();
  const upstream = (node: PromptNode): string[] =>
    Object.values(node.inputs)
      .filter((v): v is [string, number] => Array.isArray(v) && typeof v[0] === "string")
      .map((v) => v[0]);

  for (const node of Object.values(prompt)) {
    for (const id of upstream(node)) referenced.add(id);
  }

  const keep = new Set<string>();
  const stack = Object.keys(prompt).filter(
    (id) => !referenced.has(id) && !droppedOutputs.has(id),
  );
  while (stack.length) {
    const id = stack.pop()!;
    if (keep.has(id) || !prompt[id]) continue;
    keep.add(id);
    stack.push(...upstream(prompt[id]));
  }

  let removed = 0;
  for (const id of Object.keys(prompt)) {
    if (!keep.has(id)) {
      delete prompt[id];
      removed++;
    }
  }
  applied.push(`pruned ${removed} unused nodes`);
}

// --- Output -----------------------------------------------------------------

for (const line of applied) console.error(`  ${line}`);
process.stdout.write(JSON.stringify(body));
