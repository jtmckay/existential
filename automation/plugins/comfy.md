---
machine: plugin
automation: comfy
chart:
  description: Generate an image or video in ComfyUI from a workflow binding in lib/comfy/workflows/, the message body as the prompt.
  # Every param is a string: empty keeps the workflow's own value, and a binding
  # gets each one as text either way. A binding that grows a new param needs it
  # declared here too.
  data:
    # A binding in lib/comfy/workflows/, without .yml.
    type: {type: string, default: image-text}
    output_prefix: {type: string, default: ""}
    input_image: {type: string, default: ""}
    last_image: {type: string, default: ""}
    width: {type: string, default: ""}
    height: {type: string, default: ""}
    aspect_ratio: {type: string, default: ""}
    megapixels: {type: string, default: ""}
    multiple: {type: string, default: ""}
    duration: {type: string, default: ""}
    fps: {type: string, default: ""}
    length: {type: string, default: ""}
    enhance_prompt: {type: string, default: ""}
    seed: {type: string, default: ""}
    # A batch binding's item list, instead of the message body.
    items_file: {type: string, default: ""}
    # Empty means EXIST_COMFYUI_URL + /api/prompt.
    api_url: {type: string, default: ""}
  initial: generate
  states:
    generate:
      invoke: comfy
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  comfy: |
    #!/usr/bin/env bash
    # ComfyUI
    #
    # Generates an image or video via ComfyUI. `type` names a workflow binding in
    # lib/comfy/workflows/ — run with an unknown type to list them. Adding a flow is
    # adding a .json and a .yml there, and declaring any new param in
    # automation/machines/comfy.yml (decree rejects a param it does not know).
    #
    # The message body is the prompt. For a batch flow (one whose binding declares
    # `items`, e.g. image-qwen-angles) the body is instead a YAML list of
    # {prompt, output} — see that binding's header for the shape.
    #
    # Every other parameter is named by the binding and read from DECREE_DATA_<NAME>;
    # leaving one empty keeps the workflow's own value. Common ones:
    #   width / height   output size (image/WAN flows, and an override on LTX)
    #   aspect_ratio     e.g. "16:9 (Widescreen)"   } LTX size, via ResolutionSelector
    #   megapixels       e.g. 0.9                   }
    #   duration / fps   video length in seconds, and frame rate (LTX)
    #   seed             noise seed (default: random)
    #   input_image      image filename known to ComfyUI, "sub/foo.png [input]" form ok
    #   last_image       final-frame image (video-ltx-first-last)
    #   output_prefix    output filename prefix (required)
    #   items_file       path to the YAML item list, instead of the message body
    #   api_url          ComfyUI API URL (default: EXIST_COMFYUI_URL + /api/prompt)
    set -euo pipefail

    LIB_DIR="${DECREE_LIB}/comfy"
    # shellcheck source=../../lib/comfy/common.sh
    source "$LIB_DIR/common.sh"

    # ComfyUI parameters
    type="$DECREE_DATA_TYPE"
    items_file="$DECREE_DATA_ITEMS_FILE"
    api_url="${DECREE_DATA_API_URL:-${EXIST_COMFYUI_URL:-http://comfyui:8188}/api/prompt}"

    binding="$LIB_DIR/workflows/${type}.yml"
    if [ ! -f "$binding" ]; then
        echo "Error: unknown type '$type'. Available:"
        for f in "$LIB_DIR"/workflows/*.yml; do echo "  $(basename "$f" .yml)"; done
        exit 1
    fi

    body=$(comfy_read_body "$DECREE_MESSAGE") || exit 1
    if [ -n "$items_file" ]; then
        [ -f "$items_file" ] || { echo "Error: items_file not found: $items_file"; exit 1; }
        body=$(comfy_read_body "$items_file")
    fi
    if [ -z "$body" ]; then
        echo "Error: message body is empty"
        exit 1
    fi

    # Every param the binding declares, picked up from its DECREE_DATA_ variable.
    # `prompt` is the body, not a param, so it is skipped here.
    patch_input=$(jq -n '{params: {}, items: []}')
    while read -r name; do
        [ "$name" = "prompt" ] && continue
        var="DECREE_DATA_${name^^}"
        value="${!var:-}"
        [ -n "$value" ] || continue
        patch_input=$(jq --arg k "$name" --arg v "$value" '.params[$k] = $v' <<<"$patch_input")
    done < <(yq -r '.params // {} | keys | .[]' "$binding")

    if yq -e '.items' "$binding" >/dev/null 2>&1; then
        items=$(yq -o=json -I=0 '.' <<<"$body") \
            || { echo "Error: message body is not a YAML list of {prompt, output}"; exit 1; }
        patch_input=$(jq --argjson items "$items" '.items = $items' <<<"$patch_input")
    else
        patch_input=$(jq --arg text "$body" '.params.prompt = $text' <<<"$patch_input")
    fi

    echo "=== ComfyUI: $type ==="
    echo "  API:      $api_url"
    payload=$(tsx "$LIB_DIR/patch.ts" "$binding" <<<"$patch_input")

    comfy_submit "$payload" "$api_url" "$DECREE_RUN_DIR"

    if [ "$COMFY_HTTP_CODE" -ge 200 ] && [ "$COMFY_HTTP_CODE" -lt 300 ]; then
        exit 0
    else
        exit 1
    fi
lib:
  comfy/common.sh: |
    #!/usr/bin/env bash
    # Shared helpers for the comfy plugin's script (automation/plugins/comfy.md).
    # Sourced, never run directly.

    # Strip YAML frontmatter (--- delimited) and leading blank lines.
    # If no frontmatter is present, returns the entire file.
    comfy_read_body() {
        local has_fm
        has_fm=$(head -1 "$1")
        if [ "$has_fm" = "---" ]; then
            awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$1" | sed '/\S/,$!d'
        else
            sed '/\S/,$!d' "$1"
        fi
    }

    # POST $1=payload to $2=api_url, logging payload/response under $3=run_dir
    # (if set). Prints the response body and sets COMFY_HTTP_CODE.
    comfy_submit() {
        local payload="$1" api_url="$2" run_dir="$3"

        if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
            echo "$payload" > "${run_dir}/comfy-payload.json"
            echo "  Payload:  ${run_dir}/comfy-payload.json"
        fi

        local response
        response=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
          -H 'Content-Type: application/json' \
          --data-raw "$payload")

        COMFY_HTTP_CODE=$(echo "$response" | tail -1)
        local body
        body=$(echo "$response" | sed '$d')

        echo "=== Response (HTTP $COMFY_HTTP_CODE) ==="
        echo "$body"

        if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
            echo "$body" > "${run_dir}/comfy-response.json"
        fi
    }
  comfy/patch.ts: |
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
  comfy/workflows/image_flux2_text_image.json: "{\n  \"client_id\": \"70b193468f844b99ada3c47dd94e287e\",\n  \"prompt\": {\n    \"6\": {\n      \"inputs\": {\n        \"text\": \"prompt text\",\n        \"clip\": [\"38\", 0]\n      },\n      \"class_type\": \"CLIPTextEncode\",\n      \"_meta\": { \"title\": \"CLIP Text Encode (Positive Prompt)\" }\n    },\n    \"8\": {\n      \"inputs\": { \"samples\": [\"13\", 0], \"vae\": [\"10\", 0] },\n      \"class_type\": \"VAEDecode\",\n      \"_meta\": { \"title\": \"VAE Decode\" }\n    },\n    \"9\": {\n      \"inputs\": { \"filename_prefix\": \"images/example\", \"images\": [\"8\", 0] },\n      \"class_type\": \"SaveImage\",\n      \"_meta\": { \"title\": \"Save Image\" }\n    },\n    \"10\": {\n      \"inputs\": { \"vae_name\": \"flux2-vae.safetensors\" },\n      \"class_type\": \"VAELoader\",\n      \"_meta\": { \"title\": \"Load VAE\" }\n    },\n    \"12\": {\n      \"inputs\": {\n        \"unet_name\": \"flux2_dev_fp8mixed.safetensors\",\n        \"weight_dtype\": \"default\"\n      },\n      \"class_type\": \"UNETLoader\",\n      \"_meta\": { \"title\": \"Load Diffusion Model\" }\n    },\n    \"13\": {\n      \"inputs\": {\n        \"noise\": [\"25\", 0],\n        \"guider\": [\"22\", 0],\n        \"sampler\": [\"16\", 0],\n        \"sigmas\": [\"48\", 0],\n        \"latent_image\": [\"47\", 0]\n      },\n      \"class_type\": \"SamplerCustomAdvanced\",\n      \"_meta\": { \"title\": \"SamplerCustomAdvanced\" }\n    },\n    \"16\": {\n      \"inputs\": { \"sampler_name\": \"euler\" },\n      \"class_type\": \"KSamplerSelect\",\n      \"_meta\": { \"title\": \"KSamplerSelect\" }\n    },\n    \"22\": {\n      \"inputs\": { \"model\": [\"12\", 0], \"conditioning\": [\"39\", 0] },\n      \"class_type\": \"BasicGuider\",\n      \"_meta\": { \"title\": \"BasicGuider\" }\n    },\n    \"25\": {\n      \"inputs\": { \"noise_seed\": 730539084012896 },\n      \"class_type\": \"RandomNoise\",\n      \"_meta\": { \"title\": \"RandomNoise\" }\n    },\n    \"26\": {\n      \"inputs\": { \"guidance\": 4, \"conditioning\": [\"6\", 0] },\n      \"class_type\": \"FluxGuidance\",\n      \"_meta\": { \"title\": \"FluxGuidance\" }\n    },\n    \"38\": {\n      \"inputs\": {\n        \"clip_name\": \"mistral_3_small_flux2_bf16.safetensors\",\n        \"type\": \"flux2\",\n        \"device\": \"default\"\n      },\n      \"class_type\": \"CLIPLoader\",\n      \"_meta\": { \"title\": \"Load CLIP\" }\n    },\n    \"39\": {\n      \"inputs\": { \"conditioning\": [\"43\", 0] },\n      \"class_type\": \"ReferenceLatent\",\n      \"_meta\": { \"title\": \"ReferenceLatent\" }\n    },\n    \"43\": {\n      \"inputs\": { \"conditioning\": [\"26\", 0], \"latent\": [\"44\", 0] },\n      \"class_type\": \"ReferenceLatent\",\n      \"_meta\": { \"title\": \"ReferenceLatent\" }\n    },\n    \"44\": {\n      \"inputs\": { \"pixels\": [\"45\", 0], \"vae\": [\"10\", 0] },\n      \"class_type\": \"VAEEncode\",\n      \"_meta\": { \"title\": \"VAE Encode\" }\n    },\n    \"45\": {\n      \"inputs\": {\n        \"upscale_method\": \"lanczos\",\n        \"megapixels\": 1,\n        \"resolution_steps\": 1,\n        \"image\": [\"46\", 0]\n      },\n      \"class_type\": \"ImageScaleToTotalPixels\",\n      \"_meta\": { \"title\": \"ImageScaleToTotalPixels\" }\n    },\n    \"46\": {\n      \"inputs\": { \"image\": \"example.png\" },\n      \"class_type\": \"LoadImage\",\n      \"_meta\": { \"title\": \"Load Image\" }\n    },\n    \"47\": {\n      \"inputs\": { \"width\": 960, \"height\": 1664, \"batch_size\": 1 },\n      \"class_type\": \"EmptyFlux2LatentImage\",\n      \"_meta\": { \"title\": \"Empty Flux 2 Latent\" }\n    },\n    \"48\": {\n      \"inputs\": { \"steps\": 20, \"width\": 960, \"height\": 1664 },\n      \"class_type\": \"Flux2Scheduler\",\n      \"_meta\": { \"title\": \"Flux2Scheduler\" }\n    }\n  },\n  \"extra_data\": {\n    \"extra_pnginfo\": {\n      \"workflow\": {\n        \"id\": \"7c048efb-a059-44e2-970a-43e1eb472d0d\",\n        \"revision\": 0,\n        \"last_node_id\": 67,\n        \"last_link_id\": 165,\n        \"nodes\": [\n          {\n            \"id\": 48,\n            \"type\": \"Flux2Scheduler\",\n            \"pos\": [-190.01410752108893, 313.9860761244213],\n            \"size\": [266.8166809082031, 144],\n            \"flags\": {},\n            \"order\": 13,\n            \"mode\": 0,\n            \"inputs\": [\n              {\n                \"name\": \"width\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"link\": 136\n              },\n              {\n                \"name\": \"height\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"link\": 138\n              }\n            ],\n            \"outputs\": [{ \"name\": \"SIGMAS\", \"type\": \"SIGMAS\", \"links\": [132] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"Flux2Scheduler\"\n            },\n            \"widgets_values\": [20, 960, 1664]\n          },\n          {\n            \"id\": 22,\n            \"type\": \"BasicGuider\",\n            \"pos\": [-190.01410752108893, 85.99478455239108],\n            \"size\": [266.8166809082031, 72],\n            \"flags\": {},\n            \"order\": 22,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 165 },\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 153 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"GUIDER\",\n                \"type\": \"GUIDER\",\n                \"slot_index\": 0,\n                \"links\": [30]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"BasicGuider\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 40,\n            \"type\": \"VAEEncode\",\n            \"pos\": [-485.11167714363637, 1058.0069731984254],\n            \"size\": [228.75, 8],\n            \"flags\": { \"collapsed\": true },\n            \"order\": 17,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"pixels\", \"type\": \"IMAGE\", \"link\": 122 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 120 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [121] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEEncode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 42,\n            \"type\": \"LoadImage\",\n            \"pos\": [-645.9966750916013, 481.9814265758871],\n            \"size\": [328.8999938964844, 344],\n            \"flags\": {},\n            \"order\": 0,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [123] },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"LoadImage\"\n            },\n            \"widgets_values\": [\"image_flux2_input_image.png\", \"image\"]\n          },\n          {\n            \"id\": 44,\n            \"type\": \"VAEEncode\",\n            \"pos\": [-1005.9891879674415, 1058.0069731984254],\n            \"size\": [225, 8],\n            \"flags\": { \"collapsed\": true },\n            \"order\": 18,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"pixels\", \"type\": \"IMAGE\", \"link\": 126 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 127 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [125] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEEncode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 39,\n            \"type\": \"ReferenceLatent\",\n            \"pos\": [-554.3953085097025, 1106.0103791145702],\n            \"size\": [237.25, 72],\n            \"flags\": {},\n            \"order\": 21,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 145 },\n              { \"name\": \"latent\", \"shape\": 7, \"type\": \"LATENT\", \"link\": 121 }\n            ],\n            \"outputs\": [\n              { \"name\": \"CONDITIONING\", \"type\": \"CONDITIONING\", \"links\": [153] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ReferenceLatent\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 26,\n            \"type\": \"FluxGuidance\",\n            \"pos\": [-621.9949098393369, 265.9825456198922],\n            \"size\": [380.8833312988281, 80],\n            \"flags\": {},\n            \"order\": 19,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 41 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [144]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"FluxGuidance\"\n            },\n            \"widgets_values\": [4],\n            \"color\": \"#233\",\n            \"bgcolor\": \"#355\"\n          },\n          {\n            \"id\": 16,\n            \"type\": \"KSamplerSelect\",\n            \"pos\": [-190.01410752108893, 193.99425617748443],\n            \"size\": [266.8166809082031, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 1,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"SAMPLER\", \"type\": \"SAMPLER\", \"links\": [19] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"KSamplerSelect\"\n            },\n            \"widgets_values\": [\"euler\"]\n          },\n          {\n            \"id\": 43,\n            \"type\": \"ReferenceLatent\",\n            \"pos\": [-1089.9868943402703, 1106.0103791145702],\n            \"size\": [237.25, 72],\n            \"flags\": {},\n            \"order\": 20,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 144 },\n              { \"name\": \"latent\", \"shape\": 7, \"type\": \"LATENT\", \"link\": 125 }\n            ],\n            \"outputs\": [\n              { \"name\": \"CONDITIONING\", \"type\": \"CONDITIONING\", \"links\": [145] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ReferenceLatent\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 50,\n            \"type\": \"PrimitiveNode\",\n            \"pos\": [-190.01410752108893, 565.9791640958119],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 2,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"INT\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"links\": [135, 136]\n              }\n            ],\n            \"title\": \"width\",\n            \"properties\": { \"Run widget replace on values\": false },\n            \"widgets_values\": [960, \"fixed\"],\n            \"color\": \"#223\",\n            \"bgcolor\": \"#335\"\n          },\n          {\n            \"id\": 51,\n            \"type\": \"PrimitiveNode\",\n            \"pos\": [-190.01410752108893, 709.9728115892052],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 3,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"INT\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"links\": [137, 138]\n              }\n            ],\n            \"title\": \"height\",\n            \"properties\": { \"Run widget replace on values\": false },\n            \"widgets_values\": [1664, \"fixed\"],\n            \"color\": \"#223\",\n            \"bgcolor\": \"#335\"\n          },\n          {\n            \"id\": 10,\n            \"type\": \"VAELoader\",\n            \"pos\": [-1165.8025389323398, 277.99193140321734],\n            \"size\": [357.8166809082031, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 4,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"VAE\",\n                \"type\": \"VAE\",\n                \"slot_index\": 0,\n                \"links\": [120, 127, 159]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAELoader\",\n              \"models\": [\n                {\n                  \"name\": \"flux2-vae.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors\",\n                  \"directory\": \"vae\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2-vae.safetensors\"]\n          },\n          {\n            \"id\": 47,\n            \"type\": \"EmptyFlux2LatentImage\",\n            \"pos\": [133.98427620709526, 601.9733088170158],\n            \"size\": [324, 144],\n            \"flags\": {},\n            \"order\": 12,\n            \"mode\": 0,\n            \"inputs\": [\n              {\n                \"name\": \"width\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"link\": 135\n              },\n              {\n                \"name\": \"height\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"link\": 137\n              }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [161] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"EmptyFlux2LatentImage\"\n            },\n            \"widgets_values\": [960, 1664, 1]\n          },\n          {\n            \"id\": 13,\n            \"type\": \"SamplerCustomAdvanced\",\n            \"pos\": [109.98251095483067, -46.0064523249668],\n            \"size\": [326.8333435058594, 144],\n            \"flags\": {},\n            \"order\": 23,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"noise\", \"type\": \"NOISE\", \"link\": 37 },\n              { \"name\": \"guider\", \"type\": \"GUIDER\", \"link\": 30 },\n              { \"name\": \"sampler\", \"type\": \"SAMPLER\", \"link\": 19 },\n              { \"name\": \"sigmas\", \"type\": \"SIGMAS\", \"link\": 132 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 161 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"output\",\n                \"type\": \"LATENT\",\n                \"slot_index\": 0,\n                \"links\": [24]\n              },\n              { \"name\": \"denoised_output\", \"type\": \"LATENT\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"SamplerCustomAdvanced\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 41,\n            \"type\": \"ImageScaleToTotalPixels\",\n            \"pos\": [-641.0976573853251, 901.9698649987437],\n            \"size\": [324, 146.6666717529297],\n            \"flags\": {},\n            \"order\": 11,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"image\", \"type\": \"IMAGE\", \"link\": 123 }],\n            \"outputs\": [{ \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [122] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ImageScaleToTotalPixels\"\n            },\n            \"widgets_values\": [\"lanczos\", 1, 1]\n          },\n          {\n            \"id\": 8,\n            \"type\": \"VAEDecode\",\n            \"pos\": [-166.0123111217285, 901.9698649987437],\n            \"size\": [252, 72],\n            \"flags\": {},\n            \"order\": 24,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"samples\", \"type\": \"LATENT\", \"link\": 24 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 159 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [9]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEDecode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 45,\n            \"type\": \"ImageScaleToTotalPixels\",\n            \"pos\": [-1162.0091964114495, 901.9698649987437],\n            \"size\": [324, 146.6666717529297],\n            \"flags\": {},\n            \"order\": 14,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"image\", \"type\": \"IMAGE\", \"link\": 128 }],\n            \"outputs\": [{ \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [126] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ImageScaleToTotalPixels\"\n            },\n            \"widgets_values\": [\"lanczos\", 1, 1]\n          },\n          {\n            \"id\": 60,\n            \"type\": \"Note\",\n            \"pos\": [-1174.001575880389, 1286.0151776435532],\n            \"size\": [552, 97.5],\n            \"flags\": {},\n            \"order\": 5,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"properties\": {},\n            \"widgets_values\": [\n              \"Unbypass (CTRL-B) the ReferenceLatent nodes to give ref images.\\n\\nIf you want to add more reference images, you can add multiple reference images by following the pattern.\\n\\nIf you don't want any reference image, just select all ReferenceLatent nodes and then use CTRL-B to bypass them, turning the workflow into a Text to Image workflow.\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 6,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [-753.9961311431468, -57.99883179390622],\n            \"size\": [516, 121.5],\n            \"flags\": {},\n            \"order\": 15,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 117 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [41]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Positive Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"CLIPTextEncode\"\n            },\n            \"widgets_values\": [\n              \"prompt text\"\n            ],\n            \"color\": \"#232\",\n            \"bgcolor\": \"#353\"\n          },\n          {\n            \"id\": 25,\n            \"type\": \"RandomNoise\",\n            \"pos\": [-190.01410752108893, -57.99883179390622],\n            \"size\": [266.8166809082031, 80],\n            \"flags\": {},\n            \"order\": 6,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [{ \"name\": \"NOISE\", \"type\": \"NOISE\", \"links\": [37] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"RandomNoise\"\n            },\n            \"widgets_values\": [730539084012896, \"randomize\"]\n          },\n          {\n            \"id\": 46,\n            \"type\": \"LoadImage\",\n            \"pos\": [-1161.9922212441595, 469.972040792562],\n            \"size\": [328.8999938964844, 454.8999938964844],\n            \"flags\": {},\n            \"order\": 7,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [128] },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"LoadImage\"\n            },\n            \"widgets_values\": [\"example.png\", \"image\"]\n          },\n          {\n            \"id\": 9,\n            \"type\": \"SaveImage\",\n            \"pos\": [493.9768046564832, -106.00236229843523],\n            \"size\": [506.1499938964844, 922.1500244140625],\n            \"flags\": {},\n            \"order\": 25,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"images\", \"type\": \"IMAGE\", \"link\": 9 }],\n            \"outputs\": [],\n            \"properties\": { \"cnr_id\": \"comfy-core\", \"ver\": \"0.3.71\" },\n            \"widgets_values\": [\"images/example\"]\n          },\n          {\n            \"id\": 38,\n            \"type\": \"CLIPLoader\",\n            \"pos\": [-1165.8025389323398, 100.36863983015184],\n            \"size\": [357.8166809082031, 152],\n            \"flags\": {},\n            \"order\": 8,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [{ \"name\": \"CLIP\", \"type\": \"CLIP\", \"links\": [117] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"CLIPLoader\",\n              \"models\": [\n                {\n                  \"name\": \"mistral_3_small_flux2_bf16.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_bf16.safetensors\",\n                  \"directory\": \"text_encoders\"\n                }\n              ]\n            },\n            \"widgets_values\": [\n              \"mistral_3_small_flux2_bf16.safetensors\",\n              \"flux2\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 12,\n            \"type\": \"UNETLoader\",\n            \"pos\": [-1165.8025389323398, -48.387896986692226],\n            \"size\": [357.8166809082031, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 9,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [164]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"flux2_dev_fp8mixed.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2_dev_fp8mixed.safetensors\", \"default\"]\n          },\n          {\n            \"id\": 67,\n            \"type\": \"LoraLoaderModelOnly\",\n            \"pos\": [-657.9890545605408, -273.997743896997],\n            \"size\": [324, 114.66667175292969],\n            \"flags\": {},\n            \"order\": 16,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 164 }],\n            \"outputs\": [{ \"name\": \"MODEL\", \"type\": \"MODEL\", \"links\": [165] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.4.0\",\n              \"Node name for S&R\": \"LoraLoaderModelOnly\",\n              \"models\": [\n                {\n                  \"name\": \"flux2_berthe_morisot.safetensors\",\n                  \"url\": \"https://huggingface.co/ostris/flux2_berthe_morisot/resolve/main/flux2_berthe_morisot.safetensors\",\n                  \"directory\": \"loras\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2_berthe_morisot.safetensors\", 1]\n          },\n          {\n            \"id\": 66,\n            \"type\": \"MarkdownNote\",\n            \"pos\": [-1822.015349651143, -106.00236229843523],\n            \"size\": [624, 780],\n            \"flags\": { \"collapsed\": false },\n            \"order\": 10,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"Model links\",\n            \"properties\": {},\n            \"widgets_values\": [\n              \"We are using quantized weights in this workflow, the original flux 2 repo is [here](https://huggingface.co/black-forest-labs/FLUX.2-dev/)\\n## Report issue\\n\\nIf you found any issues when running this workflow, [report template issue here](https://github.com/Comfy-Org/workflow_templates/issues)\\n\\n\\n## Model links\\n\\n**text_encoders**\\n\\n- [mistral_3_small_flux2_bf16.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_bf16.safetensors)\\n\\n**loras**\\n\\n- [flux2_berthe_morisot.safetensors](https://huggingface.co/ostris/flux2_berthe_morisot/resolve/main/flux2_berthe_morisot.safetensors)\\n\\n**diffusion_models**\\n\\n- [flux2_dev_fp8mixed.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors)\\n\\n**vae**\\n\\n- [flux2-vae.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors)\\n\\n\\nModel Storage Location\\n\\n```\\n\U0001F4C2 ComfyUI/\\n├── \U0001F4C2 models/\\n│   ├── \U0001F4C2 text_encoders/\\n│   │      └── mistral_3_small_flux2_bf16.safetensors\\n│   ├── \U0001F4C2 loras/\\n│   │      └── flux2_berthe_morisot.safetensors\\n│   ├── \U0001F4C2 diffusion_models/\\n│   │      └── flux2_dev_fp8mixed.safetensors\\n│   └── \U0001F4C2 vae/\\n│          └── flux2-vae.safetensors\\n```\\n\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          }\n        ],\n        \"links\": [\n          [9, 8, 0, 9, 0, \"IMAGE\"],\n          [19, 16, 0, 13, 2, \"SAMPLER\"],\n          [24, 13, 0, 8, 0, \"LATENT\"],\n          [30, 22, 0, 13, 1, \"GUIDER\"],\n          [37, 25, 0, 13, 0, \"NOISE\"],\n          [41, 6, 0, 26, 0, \"CONDITIONING\"],\n          [117, 38, 0, 6, 0, \"CLIP\"],\n          [120, 10, 0, 40, 1, \"VAE\"],\n          [121, 40, 0, 39, 1, \"LATENT\"],\n          [122, 41, 0, 40, 0, \"IMAGE\"],\n          [123, 42, 0, 41, 0, \"IMAGE\"],\n          [125, 44, 0, 43, 1, \"LATENT\"],\n          [126, 45, 0, 44, 0, \"IMAGE\"],\n          [127, 10, 0, 44, 1, \"VAE\"],\n          [128, 46, 0, 45, 0, \"IMAGE\"],\n          [132, 48, 0, 13, 3, \"SIGMAS\"],\n          [135, 50, 0, 47, 0, \"INT\"],\n          [136, 50, 0, 48, 0, \"INT\"],\n          [137, 51, 0, 47, 1, \"INT\"],\n          [138, 51, 0, 48, 1, \"INT\"],\n          [144, 26, 0, 43, 0, \"CONDITIONING\"],\n          [145, 43, 0, 39, 0, \"CONDITIONING\"],\n          [153, 39, 0, 22, 1, \"CONDITIONING\"],\n          [159, 10, 0, 8, 1, \"VAE\"],\n          [161, 47, 0, 13, 4, \"LATENT\"],\n          [164, 12, 0, 67, 0, \"MODEL\"],\n          [165, 67, 0, 22, 0, \"MODEL\"]\n        ],\n        \"groups\": [\n          {\n            \"id\": 1,\n            \"title\": \"Step 1 - Upload models\",\n            \"bounding\": [-1174, -142, 381.81818181818176, 499.23588134765623],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 2,\n            \"title\": \"Custom sampler\",\n            \"bounding\": [-202, -142, 670.2431030273438, 601.92],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 3,\n            \"title\": \"Step 4- Image size\",\n            \"bounding\": [-202, 482, 672, 342.72],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 4,\n            \"title\": \"Step2 - Prompt\",\n            \"bounding\": [-766, -142, 540, 504],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 5,\n            \"title\": \"Step 3- Reference images\",\n            \"bounding\": [-1174, 386, 415.73227090667297, 837.5300801434184],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 6,\n            \"title\": \"Ctrl-B to Enable\",\n            \"bounding\": [-766, -370, 540, 204],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          }\n        ],\n        \"config\": {},\n        \"extra\": {\n          \"ds\": {\n            \"scale\": 0.3919155503854037,\n            \"offset\": [2764.3782127553486, 1094.6272487836547]\n          },\n          \"frontendVersion\": \"1.37.11\",\n          \"workflowRendererVersion\": \"Vue\",\n          \"groupNodes\": {},\n          \"VHS_latentpreview\": false,\n          \"VHS_latentpreviewrate\": 0,\n          \"VHS_MetadataImage\": true,\n          \"VHS_KeepIntermediate\": true\n        },\n        \"version\": 0.4\n      }\n    }\n  }\n}\n"
  comfy/workflows/image_flux2_text_landscape.json: "{\n  \"client_id\": \"70b193468f844b99ada3c47dd94e287e\",\n  \"prompt\": {\n    \"6\": {\n      \"inputs\": {\n        \"text\": \"prompt text\",\n        \"clip\": [\"38\", 0]\n      },\n      \"class_type\": \"CLIPTextEncode\",\n      \"_meta\": { \"title\": \"CLIP Text Encode (Positive Prompt)\" }\n    },\n    \"8\": {\n      \"inputs\": { \"samples\": [\"13\", 0], \"vae\": [\"10\", 0] },\n      \"class_type\": \"VAEDecode\",\n      \"_meta\": { \"title\": \"VAE Decode\" }\n    },\n    \"9\": {\n      \"inputs\": { \"filename_prefix\": \"images/example\", \"images\": [\"8\", 0] },\n      \"class_type\": \"SaveImage\",\n      \"_meta\": { \"title\": \"Save Image\" }\n    },\n    \"10\": {\n      \"inputs\": { \"vae_name\": \"flux2-vae.safetensors\" },\n      \"class_type\": \"VAELoader\",\n      \"_meta\": { \"title\": \"Load VAE\" }\n    },\n    \"12\": {\n      \"inputs\": {\n        \"unet_name\": \"flux2_dev_fp8mixed.safetensors\",\n        \"weight_dtype\": \"default\"\n      },\n      \"class_type\": \"UNETLoader\",\n      \"_meta\": { \"title\": \"Load Diffusion Model\" }\n    },\n    \"13\": {\n      \"inputs\": {\n        \"noise\": [\"25\", 0],\n        \"guider\": [\"22\", 0],\n        \"sampler\": [\"16\", 0],\n        \"sigmas\": [\"48\", 0],\n        \"latent_image\": [\"47\", 0]\n      },\n      \"class_type\": \"SamplerCustomAdvanced\",\n      \"_meta\": { \"title\": \"SamplerCustomAdvanced\" }\n    },\n    \"16\": {\n      \"inputs\": { \"sampler_name\": \"euler\" },\n      \"class_type\": \"KSamplerSelect\",\n      \"_meta\": { \"title\": \"KSamplerSelect\" }\n    },\n    \"22\": {\n      \"inputs\": { \"model\": [\"12\", 0], \"conditioning\": [\"26\", 0] },\n      \"class_type\": \"BasicGuider\",\n      \"_meta\": { \"title\": \"BasicGuider\" }\n    },\n    \"25\": {\n      \"inputs\": { \"noise_seed\": 730539084012896 },\n      \"class_type\": \"RandomNoise\",\n      \"_meta\": { \"title\": \"RandomNoise\" }\n    },\n    \"26\": {\n      \"inputs\": { \"guidance\": 4, \"conditioning\": [\"6\", 0] },\n      \"class_type\": \"FluxGuidance\",\n      \"_meta\": { \"title\": \"FluxGuidance\" }\n    },\n    \"38\": {\n      \"inputs\": {\n        \"clip_name\": \"mistral_3_small_flux2_bf16.safetensors\",\n        \"type\": \"flux2\",\n        \"device\": \"default\"\n      },\n      \"class_type\": \"CLIPLoader\",\n      \"_meta\": { \"title\": \"Load CLIP\" }\n    },\n    \"47\": {\n      \"inputs\": { \"width\": 1248, \"height\": 832, \"batch_size\": 1 },\n      \"class_type\": \"EmptyFlux2LatentImage\",\n      \"_meta\": { \"title\": \"Empty Flux 2 Latent\" }\n    },\n    \"48\": {\n      \"inputs\": { \"steps\": 20, \"width\": 1248, \"height\": 832 },\n      \"class_type\": \"Flux2Scheduler\",\n      \"_meta\": { \"title\": \"Flux2Scheduler\" }\n    }\n  },\n  \"extra_data\": {\n    \"extra_pnginfo\": {\n      \"workflow\": {\n        \"id\": \"7c048efb-a059-44e2-970a-43e1eb472d0d\",\n        \"revision\": 0,\n        \"last_node_id\": 67,\n        \"last_link_id\": 165,\n        \"nodes\": [\n          {\n            \"id\": 48,\n            \"type\": \"Flux2Scheduler\",\n            \"pos\": [-190.01617800988822, 313.9950760488025],\n            \"size\": [266.8166809082031, 144],\n            \"flags\": {},\n            \"order\": 13,\n            \"mode\": 0,\n            \"inputs\": [\n              {\n                \"name\": \"width\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"link\": 136\n              },\n              {\n                \"name\": \"height\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"link\": 138\n              }\n            ],\n            \"outputs\": [{ \"name\": \"SIGMAS\", \"type\": \"SIGMAS\", \"links\": [132] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"Flux2Scheduler\"\n            },\n            \"widgets_values\": [20, 1248, 832]\n          },\n          {\n            \"id\": 22,\n            \"type\": \"BasicGuider\",\n            \"pos\": [-190.01617800988822, 85.9867470152908],\n            \"size\": [266.8166809082031, 72],\n            \"flags\": {},\n            \"order\": 22,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 165 },\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 153 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"GUIDER\",\n                \"type\": \"GUIDER\",\n                \"slot_index\": 0,\n                \"links\": [30]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"BasicGuider\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 40,\n            \"type\": \"VAEEncode\",\n            \"pos\": [-485.11379435307936, 1058.0158485344223],\n            \"size\": [228.75, 8],\n            \"flags\": { \"collapsed\": true },\n            \"order\": 17,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"pixels\", \"type\": \"IMAGE\", \"link\": 122 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 120 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [121] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEEncode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 42,\n            \"type\": \"LoadImage\",\n            \"pos\": [-645.9987767274963, 481.9904265002683],\n            \"size\": [328.8999938964844, 344],\n            \"flags\": {},\n            \"order\": 0,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [123] },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"LoadImage\"\n            },\n            \"widgets_values\": [\"image_flux2_input_image.png\", \"image\"]\n          },\n          {\n            \"id\": 44,\n            \"type\": \"VAEEncode\",\n            \"pos\": [-1005.9912896033362, 1058.0158485344223],\n            \"size\": [228.75, 8],\n            \"flags\": { \"collapsed\": true },\n            \"order\": 18,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"pixels\", \"type\": \"IMAGE\", \"link\": 126 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 127 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [125] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEEncode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 39,\n            \"type\": \"ReferenceLatent\",\n            \"pos\": [-554.3804038312119, 1106.0024350187573],\n            \"size\": [237.25, 72],\n            \"flags\": {},\n            \"order\": 21,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 145 },\n              { \"name\": \"latent\", \"shape\": 7, \"type\": \"LATENT\", \"link\": 121 }\n            ],\n            \"outputs\": [\n              { \"name\": \"CONDITIONING\", \"type\": \"CONDITIONING\", \"links\": [153] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ReferenceLatent\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 26,\n            \"type\": \"FluxGuidance\",\n            \"pos\": [-621.9970114752318, 265.99154554427355],\n            \"size\": [380.8833312988281, 80],\n            \"flags\": {},\n            \"order\": 19,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 41 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [144]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"FluxGuidance\"\n            },\n            \"widgets_values\": [4],\n            \"color\": \"#233\",\n            \"bgcolor\": \"#355\"\n          },\n          {\n            \"id\": 16,\n            \"type\": \"KSamplerSelect\",\n            \"pos\": [-190.01617800988822, 193.98618749328818],\n            \"size\": [266.8166809082031, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 1,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"SAMPLER\", \"type\": \"SAMPLER\", \"links\": [19] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"KSamplerSelect\"\n            },\n            \"widgets_values\": [\"euler\"]\n          },\n          {\n            \"id\": 43,\n            \"type\": \"ReferenceLatent\",\n            \"pos\": [-1089.9889648290691, 1106.0024350187573],\n            \"size\": [237.25, 72],\n            \"flags\": {},\n            \"order\": 20,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"conditioning\", \"type\": \"CONDITIONING\", \"link\": 144 },\n              { \"name\": \"latent\", \"shape\": 7, \"type\": \"LATENT\", \"link\": 125 }\n            ],\n            \"outputs\": [\n              { \"name\": \"CONDITIONING\", \"type\": \"CONDITIONING\", \"links\": [145] }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ReferenceLatent\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 50,\n            \"type\": \"PrimitiveNode\",\n            \"pos\": [-190.01617800988822, 565.9710954116155],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 2,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"INT\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"links\": [135, 136]\n              }\n            ],\n            \"title\": \"width\",\n            \"properties\": { \"Run widget replace on values\": false },\n            \"widgets_values\": [1248, \"fixed\"],\n            \"color\": \"#223\",\n            \"bgcolor\": \"#335\"\n          },\n          {\n            \"id\": 51,\n            \"type\": \"PrimitiveNode\",\n            \"pos\": [-190.01617800988822, 709.9816869252023],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 3,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"INT\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"links\": [137, 138]\n              }\n            ],\n            \"title\": \"height\",\n            \"properties\": { \"Run widget replace on values\": false },\n            \"widgets_values\": [832, \"fixed\"],\n            \"color\": \"#223\",\n            \"bgcolor\": \"#335\"\n          },\n          {\n            \"id\": 10,\n            \"type\": \"VAELoader\",\n            \"pos\": [-1165.8046405682344, 277.9839250132129],\n            \"size\": [357.8166809082031, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 4,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"VAE\",\n                \"type\": \"VAE\",\n                \"slot_index\": 0,\n                \"links\": [120, 127, 159]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAELoader\",\n              \"models\": [\n                {\n                  \"name\": \"flux2-vae.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors\",\n                  \"directory\": \"vae\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2-vae.safetensors\"]\n          },\n          {\n            \"id\": 47,\n            \"type\": \"EmptyFlux2LatentImage\",\n            \"pos\": [133.98220571829575, 601.9822464472051],\n            \"size\": [324, 144],\n            \"flags\": {},\n            \"order\": 12,\n            \"mode\": 0,\n            \"inputs\": [\n              {\n                \"name\": \"width\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"width\" },\n                \"link\": 135\n              },\n              {\n                \"name\": \"height\",\n                \"type\": \"INT\",\n                \"widget\": { \"name\": \"height\" },\n                \"link\": 137\n              }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [161] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"EmptyFlux2LatentImage\"\n            },\n            \"widgets_values\": [1248, 832, 1]\n          },\n          {\n            \"id\": 13,\n            \"type\": \"SamplerCustomAdvanced\",\n            \"pos\": [109.99744678041702, -45.99745240058536],\n            \"size\": [326.8333435058594, 144],\n            \"flags\": {},\n            \"order\": 23,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"noise\", \"type\": \"NOISE\", \"link\": 37 },\n              { \"name\": \"guider\", \"type\": \"GUIDER\", \"link\": 30 },\n              { \"name\": \"sampler\", \"type\": \"SAMPLER\", \"link\": 19 },\n              { \"name\": \"sigmas\", \"type\": \"SIGMAS\", \"link\": 132 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 161 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"output\",\n                \"type\": \"LATENT\",\n                \"slot_index\": 0,\n                \"links\": [24]\n              },\n              { \"name\": \"denoised_output\", \"type\": \"LATENT\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"SamplerCustomAdvanced\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 41,\n            \"type\": \"ImageScaleToTotalPixels\",\n            \"pos\": [-641.09975902122, 901.9788649231244],\n            \"size\": [324, 146.6666717529297],\n            \"flags\": {},\n            \"order\": 11,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"image\", \"type\": \"IMAGE\", \"link\": 123 }],\n            \"outputs\": [{ \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [122] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ImageScaleToTotalPixels\"\n            },\n            \"widgets_values\": [\"lanczos\", 1, 1]\n          },\n          {\n            \"id\": 8,\n            \"type\": \"VAEDecode\",\n            \"pos\": [-166.01441275762375, 901.9788649231244],\n            \"size\": [252, 72],\n            \"flags\": {},\n            \"order\": 24,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"samples\", \"type\": \"LATENT\", \"link\": 24 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 159 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [9]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"VAEDecode\"\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 45,\n            \"type\": \"ImageScaleToTotalPixels\",\n            \"pos\": [-1162.011298047344, 901.9788649231244],\n            \"size\": [324, 146.6666717529297],\n            \"flags\": {},\n            \"order\": 14,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"image\", \"type\": \"IMAGE\", \"link\": 128 }],\n            \"outputs\": [{ \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [126] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"ImageScaleToTotalPixels\"\n            },\n            \"widgets_values\": [\"lanczos\", 1, 1]\n          },\n          {\n            \"id\": 60,\n            \"type\": \"Note\",\n            \"pos\": [-1174.0036775162837, 1286.0072335477403],\n            \"size\": [552, 97.5],\n            \"flags\": {},\n            \"order\": 5,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"properties\": {},\n            \"widgets_values\": [\n              \"Unbypass (CTRL-B) the ReferenceLatent nodes to give ref images.\\n\\nIf you want to add more reference images, you can add multiple reference images by following the pattern.\\n\\nIf you don't want any reference image, just select all ReferenceLatent nodes and then use CTRL-B to bypass them, turning the workflow into a Text to Image workflow.\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 6,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [-753.981226464656, -58.006838183910475],\n            \"size\": [529.2666625976562, 226.83334350585938],\n            \"flags\": {},\n            \"order\": 15,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 117 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [41]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Positive Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"CLIPTextEncode\"\n            },\n            \"widgets_values\": [\n              \"prompt text\"\n            ],\n            \"color\": \"#232\",\n            \"bgcolor\": \"#353\"\n          },\n          {\n            \"id\": 25,\n            \"type\": \"RandomNoise\",\n            \"pos\": [-190.01617800988822, -58.006838183910475],\n            \"size\": [266.8166809082031, 80],\n            \"flags\": {},\n            \"order\": 6,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [{ \"name\": \"NOISE\", \"type\": \"NOISE\", \"links\": [37] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"RandomNoise\"\n            },\n            \"widgets_values\": [730539084012896, \"randomize\"]\n          },\n          {\n            \"id\": 46,\n            \"type\": \"LoadImage\",\n            \"pos\": [-1162.011298047344, 469.9810407169432],\n            \"size\": [328.8999938964844, 344],\n            \"flags\": {},\n            \"order\": 7,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              { \"name\": \"IMAGE\", \"type\": \"IMAGE\", \"links\": [128] },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"LoadImage\"\n            },\n            \"widgets_values\": [\"image_flux2_input_image.png\", \"image\"]\n          },\n          {\n            \"id\": 9,\n            \"type\": \"SaveImage\",\n            \"pos\": [493.97467187349184, -106.01036868843943],\n            \"size\": [506.1499938964844, 862.1500244140625],\n            \"flags\": {},\n            \"order\": 25,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"images\", \"type\": \"IMAGE\", \"link\": 9 }],\n            \"outputs\": [],\n            \"properties\": { \"cnr_id\": \"comfy-core\", \"ver\": \"0.3.71\" },\n            \"widgets_values\": [\"images/example\"]\n          },\n          {\n            \"id\": 38,\n            \"type\": \"CLIPLoader\",\n            \"pos\": [-1165.8046405682344, 100.37763975453322],\n            \"size\": [357.8166809082031, 152],\n            \"flags\": {},\n            \"order\": 8,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [{ \"name\": \"CLIP\", \"type\": \"CLIP\", \"links\": [117] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"CLIPLoader\",\n              \"models\": [\n                {\n                  \"name\": \"mistral_3_small_flux2_bf16.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_bf16.safetensors\",\n                  \"directory\": \"text_encoders\"\n                }\n              ]\n            },\n            \"widgets_values\": [\n              \"mistral_3_small_flux2_bf16.safetensors\",\n              \"flux2\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 12,\n            \"type\": \"UNETLoader\",\n            \"pos\": [-1165.8046405682344, -48.378897062310784],\n            \"size\": [357.8166809082031, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 9,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [164]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.71\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"flux2_dev_fp8mixed.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2_dev_fp8mixed.safetensors\", \"default\"]\n          },\n          {\n            \"id\": 67,\n            \"type\": \"LoraLoaderModelOnly\",\n            \"pos\": [-657.9911561964357, -274.0057502870011],\n            \"size\": [324, 114.66667175292969],\n            \"flags\": {},\n            \"order\": 16,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 164 }],\n            \"outputs\": [{ \"name\": \"MODEL\", \"type\": \"MODEL\", \"links\": [165] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.4.0\",\n              \"Node name for S&R\": \"LoraLoaderModelOnly\",\n              \"models\": [\n                {\n                  \"name\": \"flux2_berthe_morisot.safetensors\",\n                  \"url\": \"https://huggingface.co/ostris/flux2_berthe_morisot/resolve/main/flux2_berthe_morisot.safetensors\",\n                  \"directory\": \"loras\"\n                }\n              ]\n            },\n            \"widgets_values\": [\"flux2_berthe_morisot.safetensors\", 1]\n          },\n          {\n            \"id\": 66,\n            \"type\": \"MarkdownNote\",\n            \"pos\": [-1822.0004138255558, -106.01036868843943],\n            \"size\": [624, 780],\n            \"flags\": { \"collapsed\": false },\n            \"order\": 10,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"Model links\",\n            \"properties\": {},\n            \"widgets_values\": [\n              \"We are using quantized weights in this workflow, the original flux 2 repo is [here](https://huggingface.co/black-forest-labs/FLUX.2-dev/)\\n## Report issue\\n\\nIf you found any issues when running this workflow, [report template issue here](https://github.com/Comfy-Org/workflow_templates/issues)\\n\\n\\n## Model links\\n\\n**text_encoders**\\n\\n- [mistral_3_small_flux2_bf16.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_bf16.safetensors)\\n\\n**loras**\\n\\n- [flux2_berthe_morisot.safetensors](https://huggingface.co/ostris/flux2_berthe_morisot/resolve/main/flux2_berthe_morisot.safetensors)\\n\\n**diffusion_models**\\n\\n- [flux2_dev_fp8mixed.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors)\\n\\n**vae**\\n\\n- [flux2-vae.safetensors](https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors)\\n\\n\\nModel Storage Location\\n\\n```\\n\U0001F4C2 ComfyUI/\\n├── \U0001F4C2 models/\\n│   ├── \U0001F4C2 text_encoders/\\n│   │      └── mistral_3_small_flux2_bf16.safetensors\\n│   ├── \U0001F4C2 loras/\\n│   │      └── flux2_berthe_morisot.safetensors\\n│   ├── \U0001F4C2 diffusion_models/\\n│   │      └── flux2_dev_fp8mixed.safetensors\\n│   └── \U0001F4C2 vae/\\n│          └── flux2-vae.safetensors\\n```\\n\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          }\n        ],\n        \"links\": [\n          [9, 8, 0, 9, 0, \"IMAGE\"],\n          [19, 16, 0, 13, 2, \"SAMPLER\"],\n          [24, 13, 0, 8, 0, \"LATENT\"],\n          [30, 22, 0, 13, 1, \"GUIDER\"],\n          [37, 25, 0, 13, 0, \"NOISE\"],\n          [41, 6, 0, 26, 0, \"CONDITIONING\"],\n          [117, 38, 0, 6, 0, \"CLIP\"],\n          [120, 10, 0, 40, 1, \"VAE\"],\n          [121, 40, 0, 39, 1, \"LATENT\"],\n          [122, 41, 0, 40, 0, \"IMAGE\"],\n          [123, 42, 0, 41, 0, \"IMAGE\"],\n          [125, 44, 0, 43, 1, \"LATENT\"],\n          [126, 45, 0, 44, 0, \"IMAGE\"],\n          [127, 10, 0, 44, 1, \"VAE\"],\n          [128, 46, 0, 45, 0, \"IMAGE\"],\n          [132, 48, 0, 13, 3, \"SIGMAS\"],\n          [135, 50, 0, 47, 0, \"INT\"],\n          [136, 50, 0, 48, 0, \"INT\"],\n          [137, 51, 0, 47, 1, \"INT\"],\n          [138, 51, 0, 48, 1, \"INT\"],\n          [144, 26, 0, 43, 0, \"CONDITIONING\"],\n          [145, 43, 0, 39, 0, \"CONDITIONING\"],\n          [153, 39, 0, 22, 1, \"CONDITIONING\"],\n          [159, 10, 0, 8, 1, \"VAE\"],\n          [161, 47, 0, 13, 4, \"LATENT\"],\n          [164, 12, 0, 67, 0, \"MODEL\"],\n          [165, 67, 0, 22, 0, \"MODEL\"]\n        ],\n        \"groups\": [\n          {\n            \"id\": 1,\n            \"title\": \"Step 1 - Upload models\",\n            \"bounding\": [-1174, -142, 381.81818181818176, 499.23588134765623],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 2,\n            \"title\": \"Custom sampler\",\n            \"bounding\": [-202, -142, 670.2431030273438, 601.92],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 3,\n            \"title\": \"Step 4- Image size\",\n            \"bounding\": [-202, 482, 672, 342.72],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 4,\n            \"title\": \"Step2 - Prompt\",\n            \"bounding\": [-766, -142, 540, 504],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 5,\n            \"title\": \"Step 3- Reference images\",\n            \"bounding\": [-1174, 386, 415.73227090667297, 837.5300801434184],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 6,\n            \"title\": \"Ctrl-B to Enable\",\n            \"bounding\": [-766, -370, 540, 204],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          }\n        ],\n        \"config\": {},\n        \"extra\": {\n          \"ds\": {\n            \"scale\": 0.9797888759635097,\n            \"offset\": [1586.9667950075677, 632.4948911613695]\n          },\n          \"frontendVersion\": \"1.37.11\",\n          \"workflowRendererVersion\": \"Vue\",\n          \"groupNodes\": {},\n          \"VHS_latentpreview\": false,\n          \"VHS_latentpreviewrate\": 0,\n          \"VHS_MetadataImage\": true,\n          \"VHS_KeepIntermediate\": true\n        },\n        \"version\": 0.4\n      }\n    }\n  }\n}\n"
  comfy/workflows/image-qwen-angles.yml: |
    # Qwen-Image-Edit 2511 batch: one character image edited eight ways at once.
    #
    # This is the batch flow — the message body is a YAML list of {prompt, output}
    # rather than prompt text, one entry per image you want back:
    #
    #   - prompt: Move camera facing subject, close up angle. Remove background.
    #     output: hero/front
    #   - prompt: Move camera to aerial view of subject. Remove background.
    #     output: hero/top
    #
    # One to eight entries. Fewer than eight prunes the unused branches, so they cost
    # no GPU time. Each entry may also carry its own `seed`; without one it is
    # randomized, so re-running the same batch gives fresh images.
    #
    # There is no size param: FluxKontextImageScale derives the output resolution
    # from input_image.
    workflow: images_qwen_text_image.json
    params:
      input_image:
        type: image
        required: true
        bind:
          - { node: "25", input: image }
    items:
      max: 8
      branches:
        - prompt: { node: "427:221:151", input: prompt }
          output: { node: "373", input: filename_prefix }
          seed: { node: "427:221:169", input: seed, default: random }
        - prompt: { node: "427:246:228", input: prompt }
          output: { node: "374", input: filename_prefix }
          seed: { node: "427:246:242", input: seed, default: random }
        - prompt: { node: "427:271:253", input: prompt }
          output: { node: "376", input: filename_prefix }
          seed: { node: "427:271:267", input: seed, default: random }
        - prompt: { node: "427:296:278", input: prompt }
          output: { node: "379", input: filename_prefix }
          seed: { node: "427:296:292", input: seed, default: random }
        - prompt: { node: "427:321:303", input: prompt }
          output: { node: "380", input: filename_prefix }
          seed: { node: "427:321:317", input: seed, default: random }
        - prompt: { node: "427:346:328", input: prompt }
          output: { node: "377", input: filename_prefix }
          seed: { node: "427:346:342", input: seed, default: random }
        - prompt: { node: "427:371:353", input: prompt }
          output: { node: "381", input: filename_prefix }
          seed: { node: "427:371:367", input: seed, default: random }
        - prompt: { node: "427:423:405", input: prompt }
          output: { node: "424", input: filename_prefix }
          seed: { node: "427:423:419", input: seed, default: random }
  comfy/workflows/images_qwen_text_image.json: |
    {
      "25": {
        "inputs": {
          "image": "example.png"
        },
        "class_type": "LoadImage",
        "_meta": {
          "title": "Load Character Image"
        }
      },
      "373": {
        "inputs": {
          "filename_prefix": "images/example-1",
          "images": [
            "427:221:158",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "374": {
        "inputs": {
          "filename_prefix": "images/example-2",
          "images": [
            "427:246:243",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "376": {
        "inputs": {
          "filename_prefix": "images/example-3",
          "images": [
            "427:271:268",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "377": {
        "inputs": {
          "filename_prefix": "images/example-6",
          "images": [
            "427:346:343",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "379": {
        "inputs": {
          "filename_prefix": "images/example-4",
          "images": [
            "427:296:293",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "380": {
        "inputs": {
          "filename_prefix": "images/example-5",
          "images": [
            "427:321:318",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "381": {
        "inputs": {
          "filename_prefix": "images/example-7",
          "images": [
            "427:371:368",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "424": {
        "inputs": {
          "filename_prefix": "images/example-8",
          "images": [
            "427:423:420",
            0
          ]
        },
        "class_type": "SaveImage",
        "_meta": {
          "title": "Save Image"
        }
      },
      "427:221:145": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:221:220",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:221:146": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:221:147": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:221:149",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:221:148": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:221:151",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:221:149": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:221:162",
            0
          ],
          "vae": [
            "427:221:146",
            0
          ],
          "image1": [
            "427:221:160",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:221:151": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:221:162",
            0
          ],
          "vae": [
            "427:221:146",
            0
          ],
          "image1": [
            "427:221:160",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:221:152": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:221:145",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:221:153": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:221:152",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:221:154": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:221:155": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:221:156": {
        "inputs": {
          "pixels": [
            "427:221:160",
            0
          ],
          "vae": [
            "427:221:146",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:221:161": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:221:162": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:221:163": {
        "inputs": {
          "switch": [
            "427:221:168",
            0
          ],
          "on_false": [
            "427:221:152",
            0
          ],
          "on_true": [
            "427:221:153",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:221:165": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:221:166": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:221:168": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:221:164": {
        "inputs": {
          "switch": [
            "427:221:168",
            0
          ],
          "on_false": [
            "427:221:154",
            0
          ],
          "on_true": [
            "427:221:155",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:221:167": {
        "inputs": {
          "switch": [
            "427:221:168",
            0
          ],
          "on_false": [
            "427:221:166",
            0
          ],
          "on_true": [
            "427:221:165",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:221:169": {
        "inputs": {
          "seed": 541047663446881,
          "steps": [
            "427:221:167",
            0
          ],
          "cfg": [
            "427:221:164",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:221:163",
            0
          ],
          "positive": [
            "427:221:148",
            0
          ],
          "negative": [
            "427:221:147",
            0
          ],
          "latent_image": [
            "427:221:156",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:221:158": {
        "inputs": {
          "samples": [
            "427:221:169",
            0
          ],
          "vae": [
            "427:221:146",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:221:160": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:221:220": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:221:161",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:246:222": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:246:245",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:246:223": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:246:224": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:246:226",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:246:225": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:246:228",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:246:226": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:246:235",
            0
          ],
          "vae": [
            "427:246:223",
            0
          ],
          "image1": [
            "427:246:244",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:246:228": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:246:235",
            0
          ],
          "vae": [
            "427:246:223",
            0
          ],
          "image1": [
            "427:246:244",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:246:229": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:246:222",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:246:230": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:246:229",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:246:231": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:246:232": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:246:233": {
        "inputs": {
          "pixels": [
            "427:246:244",
            0
          ],
          "vae": [
            "427:246:223",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:246:234": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:246:235": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:246:236": {
        "inputs": {
          "switch": [
            "427:246:239",
            0
          ],
          "on_false": [
            "427:246:229",
            0
          ],
          "on_true": [
            "427:246:230",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:246:237": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:246:238": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:246:239": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:246:240": {
        "inputs": {
          "switch": [
            "427:246:239",
            0
          ],
          "on_false": [
            "427:246:231",
            0
          ],
          "on_true": [
            "427:246:232",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:246:241": {
        "inputs": {
          "switch": [
            "427:246:239",
            0
          ],
          "on_false": [
            "427:246:238",
            0
          ],
          "on_true": [
            "427:246:237",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:246:242": {
        "inputs": {
          "seed": 116088950368772,
          "steps": [
            "427:246:241",
            0
          ],
          "cfg": [
            "427:246:240",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:246:236",
            0
          ],
          "positive": [
            "427:246:225",
            0
          ],
          "negative": [
            "427:246:224",
            0
          ],
          "latent_image": [
            "427:246:233",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:246:243": {
        "inputs": {
          "samples": [
            "427:246:242",
            0
          ],
          "vae": [
            "427:246:223",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:246:244": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:246:245": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:246:234",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:271:247": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:271:270",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:271:248": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:271:249": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:271:251",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:271:250": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:271:253",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:271:251": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:271:260",
            0
          ],
          "vae": [
            "427:271:248",
            0
          ],
          "image1": [
            "427:271:269",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:271:253": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:271:260",
            0
          ],
          "vae": [
            "427:271:248",
            0
          ],
          "image1": [
            "427:271:269",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:271:254": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:271:247",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:271:255": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:271:254",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:271:256": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:271:257": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:271:258": {
        "inputs": {
          "pixels": [
            "427:271:269",
            0
          ],
          "vae": [
            "427:271:248",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:271:259": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:271:260": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:271:261": {
        "inputs": {
          "switch": [
            "427:271:264",
            0
          ],
          "on_false": [
            "427:271:254",
            0
          ],
          "on_true": [
            "427:271:255",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:271:262": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:271:263": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:271:264": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:271:265": {
        "inputs": {
          "switch": [
            "427:271:264",
            0
          ],
          "on_false": [
            "427:271:256",
            0
          ],
          "on_true": [
            "427:271:257",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:271:266": {
        "inputs": {
          "switch": [
            "427:271:264",
            0
          ],
          "on_false": [
            "427:271:263",
            0
          ],
          "on_true": [
            "427:271:262",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:271:267": {
        "inputs": {
          "seed": 948798120901975,
          "steps": [
            "427:271:266",
            0
          ],
          "cfg": [
            "427:271:265",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:271:261",
            0
          ],
          "positive": [
            "427:271:250",
            0
          ],
          "negative": [
            "427:271:249",
            0
          ],
          "latent_image": [
            "427:271:258",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:271:268": {
        "inputs": {
          "samples": [
            "427:271:267",
            0
          ],
          "vae": [
            "427:271:248",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:271:269": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:271:270": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:271:259",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:296:272": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:296:295",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:296:273": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:296:274": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:296:276",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:296:275": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:296:278",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:296:276": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:296:285",
            0
          ],
          "vae": [
            "427:296:273",
            0
          ],
          "image1": [
            "427:296:294",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:296:278": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:296:285",
            0
          ],
          "vae": [
            "427:296:273",
            0
          ],
          "image1": [
            "427:296:294",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:296:279": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:296:272",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:296:280": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:296:279",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:296:281": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:296:282": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:296:283": {
        "inputs": {
          "pixels": [
            "427:296:294",
            0
          ],
          "vae": [
            "427:296:273",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:296:284": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:296:285": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:296:286": {
        "inputs": {
          "switch": [
            "427:296:289",
            0
          ],
          "on_false": [
            "427:296:279",
            0
          ],
          "on_true": [
            "427:296:280",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:296:287": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:296:288": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:296:289": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:296:290": {
        "inputs": {
          "switch": [
            "427:296:289",
            0
          ],
          "on_false": [
            "427:296:281",
            0
          ],
          "on_true": [
            "427:296:282",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:296:291": {
        "inputs": {
          "switch": [
            "427:296:289",
            0
          ],
          "on_false": [
            "427:296:288",
            0
          ],
          "on_true": [
            "427:296:287",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:296:292": {
        "inputs": {
          "seed": 400508161309512,
          "steps": [
            "427:296:291",
            0
          ],
          "cfg": [
            "427:296:290",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:296:286",
            0
          ],
          "positive": [
            "427:296:275",
            0
          ],
          "negative": [
            "427:296:274",
            0
          ],
          "latent_image": [
            "427:296:283",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:296:293": {
        "inputs": {
          "samples": [
            "427:296:292",
            0
          ],
          "vae": [
            "427:296:273",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:296:294": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:296:295": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:296:284",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:321:297": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:321:320",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:321:298": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:321:299": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:321:301",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:321:300": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:321:303",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:321:301": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:321:310",
            0
          ],
          "vae": [
            "427:321:298",
            0
          ],
          "image1": [
            "427:321:319",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:321:303": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:321:310",
            0
          ],
          "vae": [
            "427:321:298",
            0
          ],
          "image1": [
            "427:321:319",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:321:304": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:321:297",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:321:305": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:321:304",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:321:306": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:321:307": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:321:308": {
        "inputs": {
          "pixels": [
            "427:321:319",
            0
          ],
          "vae": [
            "427:321:298",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:321:309": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:321:310": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:321:311": {
        "inputs": {
          "switch": [
            "427:321:314",
            0
          ],
          "on_false": [
            "427:321:304",
            0
          ],
          "on_true": [
            "427:321:305",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:321:312": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:321:313": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:321:314": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:321:315": {
        "inputs": {
          "switch": [
            "427:321:314",
            0
          ],
          "on_false": [
            "427:321:306",
            0
          ],
          "on_true": [
            "427:321:307",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:321:316": {
        "inputs": {
          "switch": [
            "427:321:314",
            0
          ],
          "on_false": [
            "427:321:313",
            0
          ],
          "on_true": [
            "427:321:312",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:321:317": {
        "inputs": {
          "seed": 448999715597967,
          "steps": [
            "427:321:316",
            0
          ],
          "cfg": [
            "427:321:315",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:321:311",
            0
          ],
          "positive": [
            "427:321:300",
            0
          ],
          "negative": [
            "427:321:299",
            0
          ],
          "latent_image": [
            "427:321:308",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:321:318": {
        "inputs": {
          "samples": [
            "427:321:317",
            0
          ],
          "vae": [
            "427:321:298",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:321:319": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:321:320": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:321:309",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:346:322": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:346:345",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:346:323": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:346:324": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:346:326",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:346:325": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:346:328",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:346:326": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:346:335",
            0
          ],
          "vae": [
            "427:346:323",
            0
          ],
          "image1": [
            "427:346:344",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:346:328": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:346:335",
            0
          ],
          "vae": [
            "427:346:323",
            0
          ],
          "image1": [
            "427:346:344",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:346:329": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:346:322",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:346:330": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:346:329",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:346:331": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:346:332": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:346:333": {
        "inputs": {
          "pixels": [
            "427:346:344",
            0
          ],
          "vae": [
            "427:346:323",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:346:334": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:346:335": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:346:336": {
        "inputs": {
          "switch": [
            "427:346:339",
            0
          ],
          "on_false": [
            "427:346:329",
            0
          ],
          "on_true": [
            "427:346:330",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:346:337": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:346:338": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:346:339": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:346:340": {
        "inputs": {
          "switch": [
            "427:346:339",
            0
          ],
          "on_false": [
            "427:346:331",
            0
          ],
          "on_true": [
            "427:346:332",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:346:341": {
        "inputs": {
          "switch": [
            "427:346:339",
            0
          ],
          "on_false": [
            "427:346:338",
            0
          ],
          "on_true": [
            "427:346:337",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:346:342": {
        "inputs": {
          "seed": 494617165814106,
          "steps": [
            "427:346:341",
            0
          ],
          "cfg": [
            "427:346:340",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:346:336",
            0
          ],
          "positive": [
            "427:346:325",
            0
          ],
          "negative": [
            "427:346:324",
            0
          ],
          "latent_image": [
            "427:346:333",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:346:343": {
        "inputs": {
          "samples": [
            "427:346:342",
            0
          ],
          "vae": [
            "427:346:323",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:346:344": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:346:345": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:346:334",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:371:347": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:371:370",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:371:348": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:371:349": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:371:351",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:371:350": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:371:353",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:371:351": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:371:360",
            0
          ],
          "vae": [
            "427:371:348",
            0
          ],
          "image1": [
            "427:371:369",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:371:353": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:371:360",
            0
          ],
          "vae": [
            "427:371:348",
            0
          ],
          "image1": [
            "427:371:369",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:371:354": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:371:347",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:371:355": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:371:354",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:371:356": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:371:357": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:371:358": {
        "inputs": {
          "pixels": [
            "427:371:369",
            0
          ],
          "vae": [
            "427:371:348",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:371:359": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:371:360": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:371:361": {
        "inputs": {
          "switch": [
            "427:371:364",
            0
          ],
          "on_false": [
            "427:371:354",
            0
          ],
          "on_true": [
            "427:371:355",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:371:362": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:371:363": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:371:364": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:371:365": {
        "inputs": {
          "switch": [
            "427:371:364",
            0
          ],
          "on_false": [
            "427:371:356",
            0
          ],
          "on_true": [
            "427:371:357",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:371:366": {
        "inputs": {
          "switch": [
            "427:371:364",
            0
          ],
          "on_false": [
            "427:371:363",
            0
          ],
          "on_true": [
            "427:371:362",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:371:367": {
        "inputs": {
          "seed": 105282843081181,
          "steps": [
            "427:371:366",
            0
          ],
          "cfg": [
            "427:371:365",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:371:361",
            0
          ],
          "positive": [
            "427:371:350",
            0
          ],
          "negative": [
            "427:371:349",
            0
          ],
          "latent_image": [
            "427:371:358",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:371:368": {
        "inputs": {
          "samples": [
            "427:371:367",
            0
          ],
          "vae": [
            "427:371:348",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:371:369": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:371:370": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:371:359",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:423:399": {
        "inputs": {
          "shift": 3.1,
          "model": [
            "427:423:422",
            0
          ]
        },
        "class_type": "ModelSamplingAuraFlow",
        "_meta": {
          "title": "ModelSamplingAuraFlow"
        }
      },
      "427:423:400": {
        "inputs": {
          "vae_name": "qwen_image_vae.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "427:423:401": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:423:403",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:423:402": {
        "inputs": {
          "reference_latents_method": "index_timestep_zero",
          "conditioning": [
            "427:423:405",
            0
          ]
        },
        "class_type": "FluxKontextMultiReferenceLatentMethod",
        "_meta": {
          "title": "Edit Model Reference Method"
        }
      },
      "427:423:403": {
        "inputs": {
          "prompt": "",
          "clip": [
            "427:423:412",
            0
          ],
          "vae": [
            "427:423:400",
            0
          ],
          "image1": [
            "427:423:421",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus"
        }
      },
      "427:423:405": {
        "inputs": {
          "prompt": "prompt text",
          "clip": [
            "427:423:412",
            0
          ],
          "vae": [
            "427:423:400",
            0
          ],
          "image1": [
            "427:423:421",
            0
          ]
        },
        "class_type": "TextEncodeQwenImageEditPlus",
        "_meta": {
          "title": "TextEncodeQwenImageEditPlus (Positive)"
        }
      },
      "427:423:406": {
        "inputs": {
          "strength": 1,
          "pre_cfg": false,
          "model": [
            "427:423:399",
            0
          ]
        },
        "class_type": "CFGNorm",
        "_meta": {
          "title": "CFGNorm"
        }
      },
      "427:423:407": {
        "inputs": {
          "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors",
          "strength_model": 1,
          "model": [
            "427:423:406",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      },
      "427:423:408": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:423:409": {
        "inputs": {
          "value": 1
        },
        "class_type": "PrimitiveFloat",
        "_meta": {
          "title": "CFG"
        }
      },
      "427:423:410": {
        "inputs": {
          "pixels": [
            "427:423:421",
            0
          ],
          "vae": [
            "427:423:400",
            0
          ]
        },
        "class_type": "VAEEncode",
        "_meta": {
          "title": "VAE Encode"
        }
      },
      "427:423:411": {
        "inputs": {
          "unet_name": "qwen_image_edit_2511_bf16.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "427:423:412": {
        "inputs": {
          "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
          "type": "qwen_image",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "427:423:413": {
        "inputs": {
          "switch": [
            "427:423:416",
            0
          ],
          "on_false": [
            "427:423:406",
            0
          ],
          "on_true": [
            "427:423:407",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Model)"
        }
      },
      "427:423:414": {
        "inputs": {
          "value": 4
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:423:415": {
        "inputs": {
          "value": 40
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Steps"
        }
      },
      "427:423:416": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Enable 4steps LoRA?"
        }
      },
      "427:423:417": {
        "inputs": {
          "switch": [
            "427:423:416",
            0
          ],
          "on_false": [
            "427:423:408",
            0
          ],
          "on_true": [
            "427:423:409",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (CFG)"
        }
      },
      "427:423:418": {
        "inputs": {
          "switch": [
            "427:423:416",
            0
          ],
          "on_false": [
            "427:423:415",
            0
          ],
          "on_true": [
            "427:423:414",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "Switch (Steps)"
        }
      },
      "427:423:419": {
        "inputs": {
          "seed": 948882326964309,
          "steps": [
            "427:423:418",
            0
          ],
          "cfg": [
            "427:423:417",
            0
          ],
          "sampler_name": "euler",
          "scheduler": "simple",
          "denoise": 1,
          "model": [
            "427:423:413",
            0
          ],
          "positive": [
            "427:423:402",
            0
          ],
          "negative": [
            "427:423:401",
            0
          ],
          "latent_image": [
            "427:423:410",
            0
          ]
        },
        "class_type": "KSampler",
        "_meta": {
          "title": "KSampler"
        }
      },
      "427:423:420": {
        "inputs": {
          "samples": [
            "427:423:419",
            0
          ],
          "vae": [
            "427:423:400",
            0
          ]
        },
        "class_type": "VAEDecode",
        "_meta": {
          "title": "VAE Decode"
        }
      },
      "427:423:421": {
        "inputs": {
          "image": [
            "25",
            0
          ]
        },
        "class_type": "FluxKontextImageScale",
        "_meta": {
          "title": "FluxKontextImageScale"
        }
      },
      "427:423:422": {
        "inputs": {
          "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors",
          "strength_model": 1,
          "model": [
            "427:423:411",
            0
          ]
        },
        "class_type": "LoraLoaderModelOnly",
        "_meta": {
          "title": "Load LoRA"
        }
      }
    }
  comfy/workflows/image-text-image.yml: |
    # FLUX2 image-to-image: the same graph as image-text with the reference branch
    # switched on. The message body is the prompt.
    workflow: image_flux2_text_image.json
    params:
      prompt:
        required: true
        bind:
          - { node: 6, input: text, widget: 0 }
      input_image:
        type: image
        required: true
        bind:
          - { node: 46, input: image, widget: 0 }
      width:
        type: int
        align: 16
        default: 1024
        bind:
          - { node: 47, input: width, widget: 0 }
          - { node: 48, input: width, widget: 1 }
          - { node: 50, widget: 0 }
      height:
        type: int
        align: 16
        default: 1024
        bind:
          - { node: 47, input: height, widget: 1 }
          - { node: 48, input: height, widget: 2 }
          - { node: 51, widget: 0 }
      seed:
        type: int
        default: random
        bind:
          - { node: 25, input: noise_seed, widget: 0 }
        mode_bind:
          - { node: 25, widget: 1 }
      output_prefix:
        required: true
        bind:
          - { node: 9, input: filename_prefix, widget: 0 }
  comfy/workflows/image-text.yml: |
    # FLUX2 text-to-image. The message body is the prompt.
    workflow: image_flux2_text_landscape.json
    params:
      prompt:
        required: true
        bind:
          - { node: 6, input: text, widget: 0 }
      width:
        type: int
        align: 16
        default: 400
        bind:
          - { node: 47, input: width, widget: 0 }
          - { node: 48, input: width, widget: 1 }
          - { node: 50, widget: 0 }
      height:
        type: int
        align: 16
        default: 400
        bind:
          - { node: 47, input: height, widget: 1 }
          - { node: 48, input: height, widget: 2 }
          - { node: 51, widget: 0 }
      seed:
        type: int
        default: random
        bind:
          - { node: 25, input: noise_seed, widget: 0 }
        mode_bind:
          - { node: 25, widget: 1 }
      output_prefix:
        required: true
        bind:
          - { node: 9, input: filename_prefix, widget: 0 }
  comfy/workflows/video_i2v_wan2.2_14B_long.json: "{\n  \"client_id\": \"70b193468f844b99ada3c47dd94e287e\",\n  \"prompt\": {\n    \"84\": {\n      \"inputs\": {\n        \"clip_name\": \"umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n        \"type\": \"wan\",\n        \"device\": \"default\"\n      },\n      \"class_type\": \"CLIPLoader\",\n      \"_meta\": { \"title\": \"Load CLIP\" }\n    },\n    \"85\": {\n      \"inputs\": {\n        \"add_noise\": \"disable\",\n        \"noise_seed\": 0,\n        \"steps\": 4,\n        \"cfg\": 1,\n        \"sampler_name\": \"euler\",\n        \"scheduler\": \"simple\",\n        \"start_at_step\": 2,\n        \"end_at_step\": 4,\n        \"return_with_leftover_noise\": \"disable\",\n        \"model\": [\"103\", 0],\n        \"positive\": [\"98\", 0],\n        \"negative\": [\"98\", 1],\n        \"latent_image\": [\"86\", 0]\n      },\n      \"class_type\": \"KSamplerAdvanced\",\n      \"_meta\": { \"title\": \"KSampler (Advanced)\" }\n    },\n    \"86\": {\n      \"inputs\": {\n        \"add_noise\": \"enable\",\n        \"noise_seed\": 633590501442481,\n        \"steps\": 4,\n        \"cfg\": 1,\n        \"sampler_name\": \"euler\",\n        \"scheduler\": \"simple\",\n        \"start_at_step\": 0,\n        \"end_at_step\": 2,\n        \"return_with_leftover_noise\": \"enable\",\n        \"model\": [\"104\", 0],\n        \"positive\": [\"98\", 0],\n        \"negative\": [\"98\", 1],\n        \"latent_image\": [\"98\", 2]\n      },\n      \"class_type\": \"KSamplerAdvanced\",\n      \"_meta\": { \"title\": \"KSampler (Advanced)\" }\n    },\n    \"87\": {\n      \"inputs\": { \"samples\": [\"85\", 0], \"vae\": [\"90\", 0] },\n      \"class_type\": \"VAEDecode\",\n      \"_meta\": { \"title\": \"VAE Decode\" }\n    },\n    \"89\": {\n      \"inputs\": {\n        \"text\": \"色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走\",\n        \"clip\": [\"84\", 0]\n      },\n      \"class_type\": \"CLIPTextEncode\",\n      \"_meta\": { \"title\": \"CLIP Text Encode (Negative Prompt)\" }\n    },\n    \"90\": {\n      \"inputs\": { \"vae_name\": \"wan_2.1_vae.safetensors\" },\n      \"class_type\": \"VAELoader\",\n      \"_meta\": { \"title\": \"Load VAE\" }\n    },\n    \"93\": {\n      \"inputs\": {\n        \"text\": \"prompt text\",\n        \"clip\": [\"84\", 0]\n      },\n      \"class_type\": \"CLIPTextEncode\",\n      \"_meta\": { \"title\": \"CLIP Text Encode (Positive Prompt)\" }\n    },\n    \"94\": {\n      \"inputs\": { \"fps\": 16, \"images\": [\"87\", 0] },\n      \"class_type\": \"CreateVideo\",\n      \"_meta\": { \"title\": \"Create Video\" }\n    },\n    \"95\": {\n      \"inputs\": {\n        \"unet_name\": \"wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n        \"weight_dtype\": \"default\"\n      },\n      \"class_type\": \"UNETLoader\",\n      \"_meta\": { \"title\": \"Load Diffusion Model\" }\n    },\n    \"96\": {\n      \"inputs\": {\n        \"unet_name\": \"wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n        \"weight_dtype\": \"default\"\n      },\n      \"class_type\": \"UNETLoader\",\n      \"_meta\": { \"title\": \"Load Diffusion Model\" }\n    },\n    \"97\": {\n      \"inputs\": { \"image\": \"example.png\" },\n      \"class_type\": \"LoadImage\",\n      \"_meta\": { \"title\": \"Load Image\" }\n    },\n    \"98\": {\n      \"inputs\": {\n        \"width\": 480,\n        \"height\": 832,\n        \"length\": 133,\n        \"batch_size\": 1,\n        \"positive\": [\"93\", 0],\n        \"negative\": [\"89\", 0],\n        \"vae\": [\"90\", 0],\n        \"start_image\": [\"97\", 0]\n      },\n      \"class_type\": \"WanImageToVideo\",\n      \"_meta\": { \"title\": \"WanImageToVideo\" }\n    },\n    \"101\": {\n      \"inputs\": {\n        \"lora_name\": \"wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors\",\n        \"strength_model\": 1.0000000000000002,\n        \"model\": [\"95\", 0]\n      },\n      \"class_type\": \"LoraLoaderModelOnly\",\n      \"_meta\": { \"title\": \"LoraLoaderModelOnly\" }\n    },\n    \"102\": {\n      \"inputs\": {\n        \"lora_name\": \"wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\",\n        \"strength_model\": 1.0000000000000002,\n        \"model\": [\"96\", 0]\n      },\n      \"class_type\": \"LoraLoaderModelOnly\",\n      \"_meta\": { \"title\": \"LoraLoaderModelOnly\" }\n    },\n    \"103\": {\n      \"inputs\": { \"shift\": 5.000000000000001, \"model\": [\"102\", 0] },\n      \"class_type\": \"ModelSamplingSD3\",\n      \"_meta\": { \"title\": \"ModelSamplingSD3\" }\n    },\n    \"104\": {\n      \"inputs\": { \"shift\": 5.000000000000001, \"model\": [\"101\", 0] },\n      \"class_type\": \"ModelSamplingSD3\",\n      \"_meta\": { \"title\": \"ModelSamplingSD3\" }\n    },\n    \"108\": {\n      \"inputs\": {\n        \"filename_prefix\": \"video/example\",\n        \"format\": \"auto\",\n        \"codec\": \"auto\",\n        \"video\": [\"94\", 0]\n      },\n      \"class_type\": \"SaveVideo\",\n      \"_meta\": { \"title\": \"Save Video\" }\n    }\n  },\n  \"extra_data\": {\n    \"extra_pnginfo\": {\n      \"workflow\": {\n        \"id\": \"ec7da562-7e21-4dac-a0d2-f4441e1efd3b\",\n        \"revision\": 0,\n        \"last_node_id\": 116,\n        \"last_link_id\": 214,\n        \"nodes\": [\n          {\n            \"id\": 38,\n            \"type\": \"CLIPLoader\",\n            \"pos\": [85.98029663932107, 1633.976360209474],\n            \"size\": [415.6666564941406, 152],\n            \"flags\": {},\n            \"order\": 0,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"CLIP\",\n                \"type\": \"CLIP\",\n                \"slot_index\": 0,\n                \"links\": [74, 75]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPLoader\",\n              \"models\": [\n                {\n                  \"name\": \"umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n                  \"directory\": \"text_encoders\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n              \"wan\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 7,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [541.9795640107844, 1898.0109215211137],\n            \"size\": [510.3333435058594, 121.5],\n            \"flags\": {},\n            \"order\": 16,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 75 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [135]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Negative Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPTextEncode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走\"\n            ],\n            \"color\": \"#322\",\n            \"bgcolor\": \"#533\"\n          },\n          {\n            \"id\": 39,\n            \"type\": \"VAELoader\",\n            \"pos\": [85.98029663932107, 1825.9726864482163],\n            \"size\": [413.6833190917969, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 1,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"VAE\",\n                \"type\": \"VAE\",\n                \"slot_index\": 0,\n                \"links\": [76, 141]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"VAELoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan_2.1_vae.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors\",\n                  \"directory\": \"vae\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"wan_2.1_vae.safetensors\"]\n          },\n          {\n            \"id\": 54,\n            \"type\": \"ModelSamplingSD3\",\n            \"pos\": [806.0142420020509, 1321.9903226259673],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 17,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 110 }],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [147]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"ModelSamplingSD3\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [8.000000000000002]\n          },\n          {\n            \"id\": 55,\n            \"type\": \"ModelSamplingSD3\",\n            \"pos\": [806.0142420020509, 1477.9833997575342],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 18,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 112 }],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [148]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"ModelSamplingSD3\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [8]\n          },\n          {\n            \"id\": 6,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [541.9795640107844, 1657.9997619730398],\n            \"size\": [507.4166564941406, 121.5],\n            \"flags\": {},\n            \"order\": 15,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 74 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [134]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Positive Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPTextEncode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"prompt text\"\n            ],\n            \"color\": \"#232\",\n            \"bgcolor\": \"#353\"\n          },\n          {\n            \"id\": 37,\n            \"type\": \"UNETLoader\",\n            \"pos\": [85.98029663932107, 1321.9903226259673],\n            \"size\": [416.1000061035156, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 2,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [110]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 56,\n            \"type\": \"UNETLoader\",\n            \"pos\": [85.98029663932107, 1477.9833997575342],\n            \"size\": [416.1000061035156, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 3,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [112]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 63,\n            \"type\": \"WanImageToVideo\",\n            \"pos\": [577.9828131179602, 2233.988507330013],\n            \"size\": [411.1166687011719, 272],\n            \"flags\": {},\n            \"order\": 23,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 134 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 135 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 141 },\n              {\n                \"name\": \"clip_vision_output\",\n                \"shape\": 7,\n                \"type\": \"CLIP_VISION_OUTPUT\",\n                \"link\": null\n              },\n              {\n                \"name\": \"start_image\",\n                \"shape\": 7,\n                \"type\": \"IMAGE\",\n                \"link\": 133\n              }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"positive\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [136, 138]\n              },\n              {\n                \"name\": \"negative\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 1,\n                \"links\": [137, 139]\n              },\n              {\n                \"name\": \"latent\",\n                \"type\": \"LATENT\",\n                \"slot_index\": 2,\n                \"links\": [140]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"WanImageToVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [640, 640, 81, 1]\n          },\n          {\n            \"id\": 84,\n            \"type\": \"CLIPLoader\",\n            \"pos\": [74.00044929571095, 38.01106964659243],\n            \"size\": [415.6666564941406, 152],\n            \"flags\": {},\n            \"order\": 4,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"CLIP\",\n                \"type\": \"CLIP\",\n                \"slot_index\": 0,\n                \"links\": [178, 181]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPLoader\",\n              \"models\": [\n                {\n                  \"name\": \"umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n                  \"directory\": \"text_encoders\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"umt5_xxl_fp8_e4m3fn_scaled.safetensors\",\n              \"wan\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 90,\n            \"type\": \"VAELoader\",\n            \"pos\": [74.00044929571095, 229.97554234716222],\n            \"size\": [413.6833190917969, 82.66666412353516],\n            \"flags\": {},\n            \"order\": 5,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"VAE\",\n                \"type\": \"VAE\",\n                \"slot_index\": 0,\n                \"links\": [176, 185]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"VAELoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan_2.1_vae.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors\",\n                  \"directory\": \"vae\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"wan_2.1_vae.safetensors\"]\n          },\n          {\n            \"id\": 95,\n            \"type\": \"UNETLoader\",\n            \"pos\": [62.02060195210083, -274.00679230518017],\n            \"size\": [416.1000061035156, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 6,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [194]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 96,\n            \"type\": \"UNETLoader\",\n            \"pos\": [62.02060195210083, -118.01377351342683],\n            \"size\": [416.1000061035156, 117.33332824707031],\n            \"flags\": {},\n            \"order\": 7,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [196]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"UNETLoader\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n                  \"directory\": \"diffusion_models\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\",\n              \"default\"\n            ]\n          },\n          {\n            \"id\": 103,\n            \"type\": \"ModelSamplingSD3\",\n            \"pos\": [890.0007042396394, -118.01377351342683],\n            \"size\": [252, 80],\n            \"flags\": { \"collapsed\": false },\n            \"order\": 26,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 189 }],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [192]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"ModelSamplingSD3\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [5.000000000000001]\n          },\n          {\n            \"id\": 101,\n            \"type\": \"LoraLoaderModelOnly\",\n            \"pos\": [541.9795640107844, -274.00679230518017],\n            \"size\": [336, 114.66667175292969],\n            \"flags\": {},\n            \"order\": 21,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 194 }],\n            \"outputs\": [{ \"name\": \"MODEL\", \"type\": \"MODEL\", \"links\": [190] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.49\",\n              \"Node name for S&R\": \"LoraLoaderModelOnly\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors\",\n                  \"directory\": \"loras\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors\",\n              1.0000000000000002\n            ]\n          },\n          {\n            \"id\": 102,\n            \"type\": \"LoraLoaderModelOnly\",\n            \"pos\": [541.9795640107844, -118.01377351342683],\n            \"size\": [336, 114.66667175292969],\n            \"flags\": {},\n            \"order\": 22,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 196 }],\n            \"outputs\": [{ \"name\": \"MODEL\", \"type\": \"MODEL\", \"links\": [189] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.49\",\n              \"Node name for S&R\": \"LoraLoaderModelOnly\",\n              \"models\": [\n                {\n                  \"name\": \"wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\",\n                  \"url\": \"https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\",\n                  \"directory\": \"loras\"\n                }\n              ],\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\",\n              1.0000000000000002\n            ]\n          },\n          {\n            \"id\": 62,\n            \"type\": \"LoadImage\",\n            \"pos\": [97.99205586091739, 2090.007247759856],\n            \"size\": [378, 344],\n            \"flags\": {},\n            \"order\": 8,\n            \"mode\": 4,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [133]\n              },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"slot_index\": 1, \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"LoadImage\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"video_wan2_2_14B_i2v_input_image.jpg\", \"image\"]\n          },\n          {\n            \"id\": 106,\n            \"type\": \"MarkdownNote\",\n            \"pos\": [-418.0019796732078, 1214.012312162986],\n            \"size\": [444, 156],\n            \"flags\": {},\n            \"order\": 9,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"properties\": {\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"1. Box-select then use Ctrl + B to enable\\n2. If you don't want to run both groups simultaneously, don't forget to use **Ctrl + B** to disable the **fp8_scaled + 4steps LoRA** group after enabling the **fp8_scaled** group, or try the [partial - execution](https://docs.comfy.org/interface/features/partial-execution) feature.\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 67,\n            \"type\": \"Note\",\n            \"pos\": [614.0179157633086, 986.0127368170679],\n            \"size\": [468, 97.5],\n            \"flags\": {},\n            \"order\": 10,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"Video Size\",\n            \"properties\": {\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"By default, we set the video to a smaller size for users with low VRAM. If you have enough VRAM, you can change the size\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 104,\n            \"type\": \"ModelSamplingSD3\",\n            \"pos\": [890.0007042396394, -274.00679230518017],\n            \"size\": [252, 80],\n            \"flags\": {},\n            \"order\": 25,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"model\", \"type\": \"MODEL\", \"link\": 190 }],\n            \"outputs\": [\n              {\n                \"name\": \"MODEL\",\n                \"type\": \"MODEL\",\n                \"slot_index\": 0,\n                \"links\": [195]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"ModelSamplingSD3\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [5.000000000000001]\n          },\n          {\n            \"id\": 87,\n            \"type\": \"VAEDecode\",\n            \"pos\": [1273.9613864993248, 577.9966825760173],\n            \"size\": [252, 72],\n            \"flags\": {},\n            \"order\": 32,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"samples\", \"type\": \"LATENT\", \"link\": 175 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 176 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [182]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"VAEDecode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 115,\n            \"type\": \"Note\",\n            \"pos\": [37.99720018853526, -562.0012233234804],\n            \"size\": [432, 97.5],\n            \"flags\": {},\n            \"order\": 11,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"About 4 Steps LoRA\",\n            \"properties\": {\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"Using the Wan2.2 Lighting LoRA will result in the loss of video dynamics, but it will reduce the generation time. This template provides two workflows, and you can enable one as needed.\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 86,\n            \"type\": \"KSamplerAdvanced\",\n            \"pos\": [1189.9749242617363, -297.99834053057305],\n            \"size\": [365.70001220703125, 505.20001220703125],\n            \"flags\": {},\n            \"order\": 28,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 195 },\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 172 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 173 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 174 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [170] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"KSamplerAdvanced\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"enable\",\n              633590501442481,\n              \"randomize\",\n              4,\n              1,\n              \"euler\",\n              \"simple\",\n              0,\n              2,\n              \"enable\"\n            ]\n          },\n          {\n            \"id\": 85,\n            \"type\": \"KSamplerAdvanced\",\n            \"pos\": [1606.0837607523117, -297.99834053057305],\n            \"size\": [365.70001220703125, 505.20001220703125],\n            \"flags\": {},\n            \"order\": 30,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 192 },\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 168 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 169 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 170 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [175] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"KSamplerAdvanced\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"disable\",\n              0,\n              \"fixed\",\n              4,\n              1,\n              \"euler\",\n              \"simple\",\n              2,\n              4,\n              \"disable\"\n            ]\n          },\n          {\n            \"id\": 58,\n            \"type\": \"KSamplerAdvanced\",\n            \"pos\": [1489.9811145016329, 1334.0020235077502],\n            \"size\": [365.70001220703125, 606.9000244140625],\n            \"flags\": {},\n            \"order\": 29,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 148 },\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 138 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 139 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 113 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [124] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"KSamplerAdvanced\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"disable\",\n              0,\n              \"fixed\",\n              20,\n              3.5,\n              \"euler\",\n              \"simple\",\n              10,\n              10000,\n              \"disable\"\n            ]\n          },\n          {\n            \"id\": 109,\n            \"type\": \"CreateVideo\",\n            \"pos\": [1502.0246689215883, 2090.007247759856],\n            \"size\": [324, 104],\n            \"flags\": {},\n            \"order\": 33,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"images\", \"type\": \"IMAGE\", \"link\": 198 },\n              { \"name\": \"audio\", \"shape\": 7, \"type\": \"AUDIO\", \"link\": null }\n            ],\n            \"outputs\": [{ \"name\": \"VIDEO\", \"type\": \"VIDEO\", \"links\": [199] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.49\",\n              \"Node name for S&R\": \"CreateVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [16]\n          },\n          {\n            \"id\": 8,\n            \"type\": \"VAEDecode\",\n            \"pos\": [1106.0204322419474, 2101.9872117830932],\n            \"size\": [252, 72],\n            \"flags\": {},\n            \"order\": 31,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"samples\", \"type\": \"LATENT\", \"link\": 124 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 76 }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [198]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"VAEDecode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": []\n          },\n          {\n            \"id\": 57,\n            \"type\": \"KSamplerAdvanced\",\n            \"pos\": [1106.0204322419474, 1334.0020235077502],\n            \"size\": [372, 450],\n            \"flags\": {},\n            \"order\": 27,\n            \"mode\": 4,\n            \"inputs\": [\n              { \"name\": \"model\", \"type\": \"MODEL\", \"link\": 147 },\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 136 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 137 },\n              { \"name\": \"latent_image\", \"type\": \"LATENT\", \"link\": 140 }\n            ],\n            \"outputs\": [{ \"name\": \"LATENT\", \"type\": \"LATENT\", \"links\": [113] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"KSamplerAdvanced\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"enable\",\n              678723440296424,\n              \"randomize\",\n              20,\n              3.5,\n              \"euler\",\n              \"simple\",\n              0,\n              10,\n              \"enable\"\n            ]\n          },\n          {\n            \"id\": 61,\n            \"type\": \"SaveVideo\",\n            \"pos\": [1897.9970520630563, 1334.0020235077502],\n            \"size\": [1188, 1038],\n            \"flags\": {},\n            \"order\": 35,\n            \"mode\": 4,\n            \"inputs\": [{ \"name\": \"video\", \"type\": \"VIDEO\", \"link\": 199 }],\n            \"outputs\": [],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"SaveVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"video/ComfyUI\", \"auto\", \"auto\"]\n          },\n          {\n            \"id\": 66,\n            \"type\": \"MarkdownNote\",\n            \"pos\": [-562.0151219514443, -382.0166563063342],\n            \"size\": [576, 716.5999755859375],\n            \"flags\": {},\n            \"order\": 12,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"Model Links\",\n            \"properties\": {\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"[Tutorial](https://docs.comfy.org/tutorials/video/wan/wan2_2\\n)\\n\\n**Diffusion Model**\\n- [wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors)\\n- [wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors)\\n\\n**LoRA**\\n- [wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors)\\n- [wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors)\\n\\n**VAE**\\n- [wan_2.1_vae.safetensors](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors)\\n\\n**Text Encoder**   \\n- [umt5_xxl_fp8_e4m3fn_scaled.safetensors](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors)\\n\\n\\nFile save location\\n\\n```\\nComfyUI/\\n├───\U0001F4C2 models/\\n│   ├───\U0001F4C2 diffusion_models/\\n│   │   ├─── wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors\\n│   │   └─── wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors\\n│   ├───\U0001F4C2 loras/\\n│   │   ├─── wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\\n│   │   └─── wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors\\n│   ├───\U0001F4C2 text_encoders/\\n│   │   └─── umt5_xxl_fp8_e4m3fn_scaled.safetensors \\n│   └───\U0001F4C2 vae/\\n│       └── wan_2.1_vae.safetensors\\n```\\n\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 94,\n            \"type\": \"CreateVideo\",\n            \"pos\": [1621.98252672818, 554.0051343506243],\n            \"size\": [324, 104],\n            \"flags\": {},\n            \"order\": 34,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"images\", \"type\": \"IMAGE\", \"link\": 182 },\n              { \"name\": \"audio\", \"shape\": 7, \"type\": \"AUDIO\", \"link\": null }\n            ],\n            \"outputs\": [{ \"name\": \"VIDEO\", \"type\": \"VIDEO\", \"links\": [197] }],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CreateVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [16]\n          },\n          {\n            \"id\": 98,\n            \"type\": \"WanImageToVideo\",\n            \"pos\": [637.9776104505286, 637.9915965882128],\n            \"size\": [411.1166687011719, 272],\n            \"flags\": {},\n            \"order\": 24,\n            \"mode\": 0,\n            \"inputs\": [\n              { \"name\": \"positive\", \"type\": \"CONDITIONING\", \"link\": 183 },\n              { \"name\": \"negative\", \"type\": \"CONDITIONING\", \"link\": 184 },\n              { \"name\": \"vae\", \"type\": \"VAE\", \"link\": 185 },\n              {\n                \"name\": \"clip_vision_output\",\n                \"shape\": 7,\n                \"type\": \"CLIP_VISION_OUTPUT\",\n                \"link\": null\n              },\n              {\n                \"name\": \"start_image\",\n                \"shape\": 7,\n                \"type\": \"IMAGE\",\n                \"link\": 186\n              }\n            ],\n            \"outputs\": [\n              {\n                \"name\": \"positive\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [168, 172]\n              },\n              {\n                \"name\": \"negative\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 1,\n                \"links\": [169, 173]\n              },\n              {\n                \"name\": \"latent\",\n                \"type\": \"LATENT\",\n                \"slot_index\": 2,\n                \"links\": [174]\n              }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"WanImageToVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [480, 832, 133, 1]\n          },\n          {\n            \"id\": 105,\n            \"type\": \"MarkdownNote\",\n            \"pos\": [-562.0151219514443, 337.98540634831625],\n            \"size\": [576, 234.79998779296875],\n            \"flags\": {},\n            \"order\": 13,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [],\n            \"title\": \"VRAM Usage\",\n            \"properties\": {\n              \"ue_properties\": {\n                \"version\": \"7.1\",\n                \"widget_ue_connectable\": {},\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"## GPU:RTX4090D 24GB\\n\\n| Model            | Size |VRAM Usage | 1st Generation | 2nd Generation |\\n|---------------------|-------|-----------|---------------|-----------------|\\n| fp8_scaled               |640*640| 84%               | ≈  536s              | ≈ 513s                   |\\n| fp8_scaled +  4steps LoRA  | 640*640  | 83%                | ≈ 97s               | ≈ 71s                   |\"\n            ],\n            \"color\": \"#432\",\n            \"bgcolor\": \"#653\"\n          },\n          {\n            \"id\": 108,\n            \"type\": \"SaveVideo\",\n            \"pos\": [2030.030317827776, -297.99834053057305],\n            \"size\": [571.7000122070312, 995.75],\n            \"flags\": {},\n            \"order\": 36,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"video\", \"type\": \"VIDEO\", \"link\": 197 }],\n            \"outputs\": [],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.49\",\n              \"Node name for S&R\": \"SaveVideo\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"video/example\", \"auto\", \"auto\"]\n          },\n          {\n            \"id\": 97,\n            \"type\": \"LoadImage\",\n            \"pos\": [76.1989268277622, 411.52134111346516],\n            \"size\": [378, 768],\n            \"flags\": {},\n            \"order\": 14,\n            \"mode\": 0,\n            \"inputs\": [],\n            \"outputs\": [\n              {\n                \"name\": \"IMAGE\",\n                \"type\": \"IMAGE\",\n                \"slot_index\": 0,\n                \"links\": [186]\n              },\n              { \"name\": \"MASK\", \"type\": \"MASK\", \"slot_index\": 1, \"links\": null }\n            ],\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"LoadImage\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\"example.png\", \"image\"]\n          },\n          {\n            \"id\": 93,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [529.9995999875473, 110.01768454057083],\n            \"size\": [612, 121.5],\n            \"flags\": {},\n            \"order\": 20,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 181 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [183]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Positive Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPTextEncode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"prompt text\"\n            ],\n            \"color\": \"#232\",\n            \"bgcolor\": \"#353\"\n          },\n          {\n            \"id\": 89,\n            \"type\": \"CLIPTextEncode\",\n            \"pos\": [529.9995999875473, 349.997107230099],\n            \"size\": [612, 121.5],\n            \"flags\": {},\n            \"order\": 19,\n            \"mode\": 0,\n            \"inputs\": [{ \"name\": \"clip\", \"type\": \"CLIP\", \"link\": 178 }],\n            \"outputs\": [\n              {\n                \"name\": \"CONDITIONING\",\n                \"type\": \"CONDITIONING\",\n                \"slot_index\": 0,\n                \"links\": [184]\n              }\n            ],\n            \"title\": \"CLIP Text Encode (Negative Prompt)\",\n            \"properties\": {\n              \"cnr_id\": \"comfy-core\",\n              \"ver\": \"0.3.45\",\n              \"Node name for S&R\": \"CLIPTextEncode\",\n              \"ue_properties\": {\n                \"widget_ue_connectable\": {},\n                \"version\": \"7.1\",\n                \"input_ue_unconnectable\": {}\n              }\n            },\n            \"widgets_values\": [\n              \"色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走\"\n            ],\n            \"color\": \"#322\",\n            \"bgcolor\": \"#533\"\n          }\n        ],\n        \"links\": [\n          [74, 38, 0, 6, 0, \"CLIP\"],\n          [75, 38, 0, 7, 0, \"CLIP\"],\n          [76, 39, 0, 8, 1, \"VAE\"],\n          [110, 37, 0, 54, 0, \"MODEL\"],\n          [112, 56, 0, 55, 0, \"MODEL\"],\n          [113, 57, 0, 58, 3, \"LATENT\"],\n          [124, 58, 0, 8, 0, \"LATENT\"],\n          [133, 62, 0, 63, 4, \"IMAGE\"],\n          [134, 6, 0, 63, 0, \"CONDITIONING\"],\n          [135, 7, 0, 63, 1, \"CONDITIONING\"],\n          [136, 63, 0, 57, 1, \"CONDITIONING\"],\n          [137, 63, 1, 57, 2, \"CONDITIONING\"],\n          [138, 63, 0, 58, 1, \"CONDITIONING\"],\n          [139, 63, 1, 58, 2, \"CONDITIONING\"],\n          [140, 63, 2, 57, 3, \"LATENT\"],\n          [141, 39, 0, 63, 2, \"VAE\"],\n          [147, 54, 0, 57, 0, \"MODEL\"],\n          [148, 55, 0, 58, 0, \"MODEL\"],\n          [168, 98, 0, 85, 1, \"CONDITIONING\"],\n          [169, 98, 1, 85, 2, \"CONDITIONING\"],\n          [170, 86, 0, 85, 3, \"LATENT\"],\n          [172, 98, 0, 86, 1, \"CONDITIONING\"],\n          [173, 98, 1, 86, 2, \"CONDITIONING\"],\n          [174, 98, 2, 86, 3, \"LATENT\"],\n          [175, 85, 0, 87, 0, \"LATENT\"],\n          [176, 90, 0, 87, 1, \"VAE\"],\n          [178, 84, 0, 89, 0, \"CLIP\"],\n          [181, 84, 0, 93, 0, \"CLIP\"],\n          [182, 87, 0, 94, 0, \"IMAGE\"],\n          [183, 93, 0, 98, 0, \"CONDITIONING\"],\n          [184, 89, 0, 98, 1, \"CONDITIONING\"],\n          [185, 90, 0, 98, 2, \"VAE\"],\n          [186, 97, 0, 98, 4, \"IMAGE\"],\n          [189, 102, 0, 103, 0, \"MODEL\"],\n          [190, 101, 0, 104, 0, \"MODEL\"],\n          [192, 103, 0, 85, 0, \"MODEL\"],\n          [194, 95, 0, 101, 0, \"MODEL\"],\n          [195, 104, 0, 86, 0, \"MODEL\"],\n          [196, 96, 0, 102, 0, \"MODEL\"],\n          [197, 94, 0, 108, 0, \"VIDEO\"],\n          [198, 8, 0, 109, 0, \"IMAGE\"],\n          [199, 109, 0, 61, 0, \"VIDEO\"]\n        ],\n        \"groups\": [\n          {\n            \"id\": 10,\n            \"title\": \"fp8_scaled\",\n            \"bounding\": [50, 1178, 3084, 1380],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 1,\n            \"title\": \"Step1 - Load models\",\n            \"bounding\": [62, 1226, 445.23724365234375, 685.676953125],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 2,\n            \"title\": \"Step2 - Upload start_image\",\n            \"bounding\": [62, 1946, 444, 564],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 3,\n            \"title\": \"Step4 -  Prompt\",\n            \"bounding\": [530, 1574, 534.3336181640625, 557.0473022460938],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 4,\n            \"title\": \"Step3 - Video size & length\",\n            \"bounding\": [530, 2150, 528, 360],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 15,\n            \"title\": \"fp8_scaled +  4steps LoRA\",\n            \"bounding\": [38, -418, 3096, 1344],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 11,\n            \"title\": \"Step1 - Load models\",\n            \"bounding\": [50, -370, 445.23724365234375, 685.676953125],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 12,\n            \"title\": \"Step2 - Upload start_image\",\n            \"bounding\": [50, 338, 444, 564],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 13,\n            \"title\": \"Step4 -  Prompt\",\n            \"bounding\": [518, 26, 636, 504],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 14,\n            \"title\": \"Step3 - Video size & length\",\n            \"bounding\": [518, 554, 636, 348],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          },\n          {\n            \"id\": 16,\n            \"title\": \"Lightx2v 4steps LoRA\",\n            \"bounding\": [518, -370, 636, 372],\n            \"color\": \"#3f789e\",\n            \"font_size\": 24,\n            \"flags\": {}\n          }\n        ],\n        \"config\": {},\n        \"extra\": {\n          \"ds\": {\n            \"scale\": 0.5231003716419486,\n            \"offset\": [454.70621080953015, 546.4714035402208]\n          },\n          \"frontendVersion\": \"1.37.11\",\n          \"workflowRendererVersion\": \"Vue\",\n          \"VHS_latentpreview\": false,\n          \"VHS_latentpreviewrate\": 0,\n          \"VHS_MetadataImage\": true,\n          \"VHS_KeepIntermediate\": true,\n          \"ue_links\": []\n        },\n        \"version\": 0.4\n      }\n    }\n  }\n}\n"
  comfy/workflows/video-i2v.yml: |
    # WAN 2.2 14B image-to-video. The message body is the prompt.
    workflow: video_i2v_wan2.2_14B_long.json
    params:
      prompt:
        required: true
        bind:
          - { node: 93, input: text, widget: 0 }
      input_image:
        type: image
        required: true
        bind:
          - { node: 97, input: image, widget: 0 }
      width:
        type: int
        align: 16
        default: 640
        bind:
          - { node: 98, input: width, widget: 0 }
      height:
        type: int
        align: 16
        default: 640
        bind:
          - { node: 98, input: height, widget: 1 }
      # Frame count, not seconds. 133 frames is the template's own length.
      length:
        type: int
        bind:
          - { node: 98, input: length, widget: 2 }
      output_prefix:
        required: true
        bind:
          - { node: 108, input: filename_prefix, widget: 0 }
  comfy/workflows/video_ltx2_5_first_last.json: |
    {
      "31": {
        "inputs": {
          "image": "example-first.png"
        },
        "class_type": "LoadImage",
        "_meta": {
          "title": "Load First Frame"
        }
      },
      "39": {
        "inputs": {
          "image": "example-last.png"
        },
        "class_type": "LoadImage",
        "_meta": {
          "title": "Load Last Frame"
        }
      },
      "68": {
        "inputs": {
          "filename_prefix": "video/example",
          "format": "auto",
          "format.codec": "auto",
          "codec": "auto",
          "video": [
            "251:218",
            0
          ]
        },
        "class_type": "SaveVideo",
        "_meta": {
          "title": "Save Video"
        }
      },
      "251:210": {
        "inputs": {
          "video_latent": [
            "251:204",
            2
          ],
          "audio_latent": [
            "251:197",
            0
          ]
        },
        "class_type": "LTXVConcatAVLatent",
        "_meta": {
          "title": "Concat AV Latent"
        }
      },
      "251:219": {
        "inputs": {
          "tile_size": 512,
          "overlap": 64,
          "temporal_size": 64,
          "temporal_overlap": 16,
          "samples": [
            "251:200",
            2
          ],
          "vae": [
            "251:229",
            0
          ]
        },
        "class_type": "VAEDecodeTiled",
        "_meta": {
          "title": "VAE Decode (Tiled)"
        }
      },
      "251:220": {
        "inputs": {
          "samples": [
            "251:221",
            1
          ],
          "audio_vae": [
            "251:227",
            0
          ]
        },
        "class_type": "LTXVAudioVAEDecode",
        "_meta": {
          "title": "LTXV Audio VAE Decode"
        }
      },
      "251:221": {
        "inputs": {
          "av_latent": [
            "251:211",
            1
          ]
        },
        "class_type": "LTXVSeparateAVLatent",
        "_meta": {
          "title": "Separate AV Latent"
        }
      },
      "251:206": {
        "inputs": {
          "frame_idx": 0,
          "strength": 0.7,
          "positive": [
            "251:202",
            0
          ],
          "negative": [
            "251:202",
            1
          ],
          "vae": [
            "251:229",
            0
          ],
          "latent": [
            "251:201",
            0
          ],
          "image": [
            "251:199",
            0
          ]
        },
        "class_type": "LTXVAddGuide",
        "_meta": {
          "title": "LTXVAddGuide"
        }
      },
      "251:239": {
        "inputs": {
          "sigmas": "1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0"
        },
        "class_type": "ManualSigmas",
        "_meta": {
          "title": "ManualSigmas"
        }
      },
      "251:204": {
        "inputs": {
          "frame_idx": -1,
          "strength": 0.7,
          "positive": [
            "251:206",
            0
          ],
          "negative": [
            "251:206",
            1
          ],
          "vae": [
            "251:229",
            0
          ],
          "latent": [
            "251:206",
            2
          ],
          "image": [
            "251:195",
            0
          ]
        },
        "class_type": "LTXVAddGuide",
        "_meta": {
          "title": "LTXVAddGuide"
        }
      },
      "251:197": {
        "inputs": {
          "frames_number": [
            "251:226",
            1
          ],
          "frame_rate": [
            "251:205",
            0
          ],
          "batch_size": 1,
          "audio_vae": [
            "251:227",
            0
          ]
        },
        "class_type": "LTXVEmptyLatentAudio",
        "_meta": {
          "title": "LTXV Empty Latent Audio"
        }
      },
      "251:200": {
        "inputs": {
          "positive": [
            "251:204",
            0
          ],
          "negative": [
            "251:204",
            1
          ],
          "latent": [
            "251:221",
            0
          ]
        },
        "class_type": "LTXVCropGuides",
        "_meta": {
          "title": "LTXVCropGuides"
        }
      },
      "251:201": {
        "inputs": {
          "width": [
            "251:203",
            0
          ],
          "height": [
            "251:203",
            1
          ],
          "length": [
            "251:226",
            1
          ],
          "batch_size": 1
        },
        "class_type": "EmptyLTXVLatentVideo",
        "_meta": {
          "title": "EmptyLTXVLatentVideo"
        }
      },
      "251:211": {
        "inputs": {
          "noise": [
            "251:196",
            0
          ],
          "guider": [
            "251:235",
            0
          ],
          "sampler": [
            "251:208",
            0
          ],
          "sigmas": [
            "251:239",
            0
          ],
          "latent_image": [
            "251:210",
            0
          ]
        },
        "class_type": "SamplerCustomAdvanced",
        "_meta": {
          "title": "SamplerCustomAdvanced"
        }
      },
      "251:202": {
        "inputs": {
          "frame_rate": [
            "251:212",
            0
          ],
          "positive": [
            "251:222",
            0
          ],
          "negative": [
            "251:217",
            0
          ]
        },
        "class_type": "LTXVConditioning",
        "_meta": {
          "title": "LTXVConditioning"
        }
      },
      "251:208": {
        "inputs": {
          "eta": 0,
          "s_noise": 1
        },
        "class_type": "SamplerEulerAncestral",
        "_meta": {
          "title": "SamplerEulerAncestral"
        }
      },
      "251:218": {
        "inputs": {
          "fps": [
            "251:212",
            0
          ],
          "bit_depth": 8,
          "color_space": "sRGB",
          "images": [
            "251:219",
            0
          ],
          "audio": [
            "251:220",
            0
          ]
        },
        "class_type": "CreateVideo",
        "_meta": {
          "title": "Create Video"
        }
      },
      "251:235": {
        "inputs": {
          "video_cfg": 1,
          "audio_cfg": 1,
          "model": [
            "251:230",
            0
          ],
          "positive": [
            "251:204",
            0
          ],
          "negative": [
            "251:204",
            1
          ]
        },
        "class_type": "LTXVDualCFGGuider",
        "_meta": {
          "title": "LTXV Dual CFG Guider"
        }
      },
      "251:196": {
        "inputs": {
          "noise_seed": 873293130933086
        },
        "class_type": "RandomNoise",
        "_meta": {
          "title": "RandomNoise"
        }
      },
      "251:217": {
        "inputs": {
          "text": "",
          "clip": [
            "251:228",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "251:222": {
        "inputs": {
          "text": [
            "251:248",
            0
          ],
          "clip": [
            "251:228",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "251:248": {
        "inputs": {
          "switch": [
            "251:250",
            0
          ],
          "on_false": [
            "251:252",
            0
          ],
          "on_true": [
            "251:247",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "If/Else Switch"
        }
      },
      "251:203": {
        "inputs": {
          "image": [
            "251:213",
            0
          ]
        },
        "class_type": "GetImageSize",
        "_meta": {
          "title": "Get Image Size"
        }
      },
      "251:195": {
        "inputs": {
          "img_compression": 18,
          "image": [
            "251:214",
            0
          ]
        },
        "class_type": "LTXVPreprocess",
        "_meta": {
          "title": "LTXV Preprocess"
        }
      },
      "251:199": {
        "inputs": {
          "img_compression": 18,
          "image": [
            "251:213",
            0
          ]
        },
        "class_type": "LTXVPreprocess",
        "_meta": {
          "title": "LTXV Preprocess"
        }
      },
      "251:247": {
        "inputs": {
          "prompt": [
            "251:252",
            0
          ],
          "max_length": 600,
          "sampling_mode": "on",
          "sampling_mode.temperature": 0.7,
          "sampling_mode.top_k": 64,
          "sampling_mode.top_p": 0.95,
          "sampling_mode.min_p": 0.05,
          "sampling_mode.repetition_penalty": 1.15,
          "sampling_mode.seed": 0,
          "sampling_mode.presence_penalty": 0,
          "thinking": false,
          "use_default_template": true,
          "clip": [
            "251:246",
            0
          ],
          "image": [
            "251:199",
            0
          ]
        },
        "class_type": "TextGenerateLTX2Prompt",
        "_meta": {
          "title": "Generate LTX2 Prompt"
        }
      },
      "251:213": {
        "inputs": {
          "resize_type": "scale dimensions",
          "resize_type.width": [
            "251:215",
            0
          ],
          "resize_type.height": [
            "251:216",
            0
          ],
          "resize_type.crop": "center",
          "scale_method": "nearest-exact",
          "input": [
            "31",
            0
          ]
        },
        "class_type": "ResizeImageMaskNode",
        "_meta": {
          "title": "Resize Image/Mask"
        }
      },
      "251:214": {
        "inputs": {
          "resize_type": "scale dimensions",
          "resize_type.width": [
            "251:215",
            0
          ],
          "resize_type.height": [
            "251:216",
            0
          ],
          "resize_type.crop": "center",
          "scale_method": "nearest-exact",
          "input": [
            "39",
            0
          ]
        },
        "class_type": "ResizeImageMaskNode",
        "_meta": {
          "title": "Resize Image/Mask"
        }
      },
      "251:249": {
        "inputs": {
          "source": [
            "251:248",
            0
          ]
        },
        "class_type": "PreviewAny",
        "_meta": {
          "title": "Preview as Text"
        }
      },
      "251:230": {
        "inputs": {
          "unet_name": "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "251:229": {
        "inputs": {
          "vae_name": "ltx-2.5-video-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "251:227": {
        "inputs": {
          "vae_name": "ltx-2.5-audio-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "251:228": {
        "inputs": {
          "clip_name": "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "251:246": {
        "inputs": {
          "clip_name": "gemma4_e2b_it_bf16.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "251:250": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Boolean (Enable Prompt Enhance)"
        }
      },
      "251:215": {
        "inputs": {
          "value": 1280
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Width"
        }
      },
      "251:216": {
        "inputs": {
          "value": 720
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "height"
        }
      },
      "251:212": {
        "inputs": {
          "expression": "a",
          "values.a": [
            "251:205",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "251:198": {
        "inputs": {
          "value": 5
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Duration"
        }
      },
      "251:226": {
        "inputs": {
          "expression": "a * b + 1",
          "values.a": [
            "251:198",
            0
          ],
          "values.b": [
            "251:205",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "251:205": {
        "inputs": {
          "value": 24
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Frame Rate(int)"
        }
      },
      "251:252": {
        "inputs": {
          "value": "prompt text"
        },
        "class_type": "PrimitiveStringMultiline",
        "_meta": {
          "title": "Prompt"
        }
      }
    }
  comfy/workflows/video_ltx2_5_image.json: |
    {
      "75": {
        "inputs": {
          "filename_prefix": "video/example",
          "format": "auto",
          "format.codec": "auto",
          "codec": "auto",
          "video": [
            "398:370",
            0
          ]
        },
        "class_type": "SaveVideo",
        "_meta": {
          "title": "Save Video"
        }
      },
      "395": {
        "inputs": {
          "image": "example.png"
        },
        "class_type": "LoadImage",
        "_meta": {
          "title": "Load First Frame"
        }
      },
      "403": {
        "inputs": {
          "aspect_ratio": "16:9 (Widescreen)",
          "megapixels": 0.9,
          "multiple": 32
        },
        "class_type": "ResolutionSelector",
        "_meta": {
          "title": "Resolution Selector"
        }
      },
      "398:393": {
        "inputs": {
          "clip_name": "gemma4_e2b_it_bf16.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "398:380": {
        "inputs": {
          "prompt": [
            "398:376",
            0
          ],
          "max_length": 600,
          "sampling_mode": "on",
          "sampling_mode.temperature": 0.7,
          "sampling_mode.top_k": 64,
          "sampling_mode.top_p": 0.95,
          "sampling_mode.min_p": 0.05,
          "sampling_mode.repetition_penalty": 1.15,
          "sampling_mode.seed": 0,
          "sampling_mode.presence_penalty": 0,
          "thinking": false,
          "use_default_template": true,
          "clip": [
            "398:393",
            0
          ],
          "image": [
            "398:350",
            0
          ]
        },
        "class_type": "TextGenerateLTX2Prompt",
        "_meta": {
          "title": "Generate LTX2 Prompt"
        }
      },
      "398:383": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Boolean (Enable Prompt Enhance)"
        }
      },
      "398:364": {
        "inputs": {
          "text": [
            "398:382",
            0
          ],
          "clip": [
            "398:387",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "398:376": {
        "inputs": {
          "value": "prompt text"
        },
        "class_type": "PrimitiveStringMultiline",
        "_meta": {
          "title": "Prompt"
        }
      },
      "398:382": {
        "inputs": {
          "switch": [
            "398:383",
            0
          ],
          "on_false": [
            "398:376",
            0
          ],
          "on_true": [
            "398:380",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "If/Else Switch"
        }
      },
      "398:384": {
        "inputs": {
          "unet_name": "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "398:381": {
        "inputs": {
          "source": [
            "398:382",
            0
          ]
        },
        "class_type": "PreviewAny",
        "_meta": {
          "title": "Preview as Text"
        }
      },
      "398:362": {
        "inputs": {
          "value": 8
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Duration"
        }
      },
      "398:363": {
        "inputs": {
          "value": false
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Switch to Text to Video?"
        }
      },
      "398:365": {
        "inputs": {
          "frame_rate": [
            "398:359",
            0
          ],
          "positive": [
            "398:364",
            0
          ],
          "negative": [
            "398:373",
            0
          ]
        },
        "class_type": "LTXVConditioning",
        "_meta": {
          "title": "LTXVConditioning"
        }
      },
      "398:385": {
        "inputs": {
          "vae_name": "ltx-2.5-video-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "398:386": {
        "inputs": {
          "vae_name": "ltx-2.5-audio-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "398:372": {
        "inputs": {
          "value": [
            "403",
            0
          ]
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Width"
        }
      },
      "398:373": {
        "inputs": {
          "text": "",
          "clip": [
            "398:387",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "398:387": {
        "inputs": {
          "clip_name": "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "398:360": {
        "inputs": {
          "value": [
            "403",
            1
          ]
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Height"
        }
      },
      "398:352": {
        "inputs": {
          "sampler_name": "euler_ancestral"
        },
        "class_type": "KSamplerSelect",
        "_meta": {
          "title": "KSamplerSelect"
        }
      },
      "398:339": {
        "inputs": {
          "noise_seed": 822085296012466
        },
        "class_type": "RandomNoise",
        "_meta": {
          "title": "RandomNoise"
        }
      },
      "398:397": {
        "inputs": {
          "sigmas": "1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0"
        },
        "class_type": "ManualSigmas",
        "_meta": {
          "title": "ManualSigmas"
        }
      },
      "398:361": {
        "inputs": {
          "value": 24
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Frame Rate"
        }
      },
      "398:371": {
        "inputs": {
          "model_name": "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
        },
        "class_type": "LatentUpscaleModelLoader",
        "_meta": {
          "title": "Load Latent Upscale Model"
        }
      },
      "398:388": {
        "inputs": {
          "video_cfg": 1,
          "audio_cfg": 1,
          "model": [
            "398:384",
            0
          ],
          "positive": [
            "398:365",
            0
          ],
          "negative": [
            "398:365",
            1
          ]
        },
        "class_type": "LTXVDualCFGGuider",
        "_meta": {
          "title": "LTXV Dual CFG Guider"
        }
      },
      "398:344": {
        "inputs": {
          "noise": [
            "398:339",
            0
          ],
          "guider": [
            "398:388",
            0
          ],
          "sampler": [
            "398:352",
            0
          ],
          "sigmas": [
            "398:397",
            0
          ],
          "latent_image": [
            "398:377",
            0
          ]
        },
        "class_type": "SamplerCustomAdvanced",
        "_meta": {
          "title": "SamplerCustomAdvanced"
        }
      },
      "398:357": {
        "inputs": {
          "strength": 0.7,
          "bypass": [
            "398:363",
            0
          ],
          "vae": [
            "398:385",
            0
          ],
          "image": [
            "398:350",
            0
          ],
          "latent": [
            "398:356",
            0
          ]
        },
        "class_type": "LTXVImgToVideoInplace",
        "_meta": {
          "title": "LTXVImgToVideoInplace"
        }
      },
      "398:366": {
        "inputs": {
          "frames_number": [
            "398:378",
            1
          ],
          "frame_rate": [
            "398:359",
            1
          ],
          "batch_size": 1,
          "audio_vae": [
            "398:386",
            0
          ]
        },
        "class_type": "LTXVEmptyLatentAudio",
        "_meta": {
          "title": "LTXV Empty Latent Audio"
        }
      },
      "398:367": {
        "inputs": {
          "av_latent": [
            "398:344",
            0
          ]
        },
        "class_type": "LTXVSeparateAVLatent",
        "_meta": {
          "title": "Separate AV Latent"
        }
      },
      "398:377": {
        "inputs": {
          "video_latent": [
            "398:357",
            0
          ],
          "audio_latent": [
            "398:366",
            0
          ]
        },
        "class_type": "LTXVConcatAVLatent",
        "_meta": {
          "title": "Concat AV Latent"
        }
      },
      "398:351": {
        "inputs": {
          "resize_type": "scale longer dimension",
          "resize_type.longer_size": 1536,
          "scale_method": "lanczos",
          "input": [
            "395",
            0
          ]
        },
        "class_type": "ResizeImageMaskNode",
        "_meta": {
          "title": "Resize Image/Mask"
        }
      },
      "398:353": {
        "inputs": {
          "expression": "a/2",
          "values.a": [
            "398:372",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "398:355": {
        "inputs": {
          "expression": "a/2",
          "values.a": [
            "398:360",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "398:350": {
        "inputs": {
          "img_compression": 18,
          "image": [
            "398:351",
            0
          ]
        },
        "class_type": "LTXVPreprocess",
        "_meta": {
          "title": "LTXV Preprocess"
        }
      },
      "398:356": {
        "inputs": {
          "width": [
            "398:353",
            1
          ],
          "height": [
            "398:355",
            1
          ],
          "length": [
            "398:378",
            1
          ],
          "batch_size": 1
        },
        "class_type": "EmptyLTXVLatentVideo",
        "_meta": {
          "title": "EmptyLTXVLatentVideo"
        }
      },
      "398:348": {
        "inputs": {
          "samples": [
            "398:367",
            0
          ],
          "upscale_model": [
            "398:371",
            0
          ],
          "vae": [
            "398:385",
            0
          ]
        },
        "class_type": "LTXVLatentUpsampler",
        "_meta": {
          "title": "LTXVLatentUpsampler"
        }
      },
      "398:349": {
        "inputs": {
          "strength": 1,
          "bypass": [
            "398:363",
            0
          ],
          "vae": [
            "398:385",
            0
          ],
          "image": [
            "398:350",
            0
          ],
          "latent": [
            "398:348",
            0
          ]
        },
        "class_type": "LTXVImgToVideoInplace",
        "_meta": {
          "title": "LTXVImgToVideoInplace"
        }
      },
      "398:359": {
        "inputs": {
          "expression": "a",
          "values.a": [
            "398:361",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression (fps)"
        }
      },
      "398:378": {
        "inputs": {
          "expression": "a * b + 1",
          "values.a": [
            "398:362",
            0
          ],
          "values.b": [
            "398:361",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression (length)"
        }
      },
      "398:338": {
        "inputs": {
          "noise_seed": 42
        },
        "class_type": "RandomNoise",
        "_meta": {
          "title": "RandomNoise"
        }
      },
      "398:340": {
        "inputs": {
          "video_latent": [
            "398:349",
            0
          ],
          "audio_latent": [
            "398:367",
            1
          ]
        },
        "class_type": "LTXVConcatAVLatent",
        "_meta": {
          "title": "Concat AV Latent"
        }
      },
      "398:396": {
        "inputs": {
          "sigmas": "0.85, 0.7250, 0.4219, 0.0"
        },
        "class_type": "ManualSigmas",
        "_meta": {
          "title": "ManualSigmas"
        }
      },
      "398:391": {
        "inputs": {
          "video_cfg": 1,
          "audio_cfg": 1,
          "model": [
            "398:384",
            0
          ],
          "positive": [
            "398:365",
            0
          ],
          "negative": [
            "398:365",
            1
          ]
        },
        "class_type": "LTXVDualCFGGuider",
        "_meta": {
          "title": "LTXV Dual CFG Guider"
        }
      },
      "398:341": {
        "inputs": {
          "sampler_name": "euler_ancestral"
        },
        "class_type": "KSamplerSelect",
        "_meta": {
          "title": "KSamplerSelect"
        }
      },
      "398:368": {
        "inputs": {
          "noise": [
            "398:338",
            0
          ],
          "guider": [
            "398:391",
            0
          ],
          "sampler": [
            "398:341",
            0
          ],
          "sigmas": [
            "398:396",
            0
          ],
          "latent_image": [
            "398:340",
            0
          ]
        },
        "class_type": "SamplerCustomAdvanced",
        "_meta": {
          "title": "SamplerCustomAdvanced"
        }
      },
      "398:369": {
        "inputs": {
          "av_latent": [
            "398:368",
            0
          ]
        },
        "class_type": "LTXVSeparateAVLatent",
        "_meta": {
          "title": "Separate AV Latent"
        }
      },
      "398:374": {
        "inputs": {
          "tile_size": 512,
          "overlap": 64,
          "temporal_size": 64,
          "temporal_overlap": 16,
          "samples": [
            "398:369",
            0
          ],
          "vae": [
            "398:385",
            0
          ]
        },
        "class_type": "VAEDecodeTiled",
        "_meta": {
          "title": "VAE Decode (Tiled)"
        }
      },
      "398:358": {
        "inputs": {
          "samples": [
            "398:369",
            1
          ],
          "audio_vae": [
            "398:386",
            0
          ]
        },
        "class_type": "LTXVAudioVAEDecode",
        "_meta": {
          "title": "LTXV Audio VAE Decode"
        }
      },
      "398:370": {
        "inputs": {
          "fps": [
            "398:359",
            0
          ],
          "bit_depth": 8,
          "color_space": "sRGB",
          "images": [
            "398:374",
            0
          ],
          "audio": [
            "398:358",
            0
          ]
        },
        "class_type": "CreateVideo",
        "_meta": {
          "title": "Create Video"
        }
      }
    }
  comfy/workflows/video_ltx2_5_text.json: |
    {
      "75": {
        "inputs": {
          "filename_prefix": "video/example",
          "format": "auto",
          "format.codec": "auto",
          "codec": "auto",
          "video": [
            "405:370",
            0
          ]
        },
        "class_type": "SaveVideo",
        "_meta": {
          "title": "Save Video"
        }
      },
      "409": {
        "inputs": {
          "aspect_ratio": "16:9 (Widescreen)",
          "megapixels": 0.9,
          "multiple": 32
        },
        "class_type": "ResolutionSelector",
        "_meta": {
          "title": "Resolution Selector"
        }
      },
      "405:370": {
        "inputs": {
          "fps": [
            "405:359",
            0
          ],
          "bit_depth": 8,
          "color_space": "sRGB",
          "images": [
            "405:374",
            0
          ],
          "audio": [
            "405:358",
            0
          ]
        },
        "class_type": "CreateVideo",
        "_meta": {
          "title": "Create Video"
        }
      },
      "405:340": {
        "inputs": {
          "video_latent": [
            "405:348",
            0
          ],
          "audio_latent": [
            "405:367",
            1
          ]
        },
        "class_type": "LTXVConcatAVLatent",
        "_meta": {
          "title": "Concat AV Latent"
        }
      },
      "405:395": {
        "inputs": {
          "sigmas": "0.85, 0.7250, 0.4219, 0.0"
        },
        "class_type": "ManualSigmas",
        "_meta": {
          "title": "ManualSigmas"
        }
      },
      "405:348": {
        "inputs": {
          "samples": [
            "405:367",
            0
          ],
          "upscale_model": [
            "405:371",
            0
          ],
          "vae": [
            "405:385",
            0
          ]
        },
        "class_type": "LTXVLatentUpsampler",
        "_meta": {
          "title": "LTXVLatentUpsampler"
        }
      },
      "405:358": {
        "inputs": {
          "samples": [
            "405:369",
            1
          ],
          "audio_vae": [
            "405:386",
            0
          ]
        },
        "class_type": "LTXVAudioVAEDecode",
        "_meta": {
          "title": "LTXV Audio VAE Decode"
        }
      },
      "405:341": {
        "inputs": {
          "sampler_name": "euler_ancestral"
        },
        "class_type": "KSamplerSelect",
        "_meta": {
          "title": "KSamplerSelect"
        }
      },
      "405:391": {
        "inputs": {
          "video_cfg": 1,
          "audio_cfg": 1,
          "model": [
            "405:384",
            0
          ],
          "positive": [
            "405:365",
            0
          ],
          "negative": [
            "405:365",
            1
          ]
        },
        "class_type": "LTXVDualCFGGuider",
        "_meta": {
          "title": "LTXV Dual CFG Guider"
        }
      },
      "405:368": {
        "inputs": {
          "noise": [
            "405:338",
            0
          ],
          "guider": [
            "405:391",
            0
          ],
          "sampler": [
            "405:341",
            0
          ],
          "sigmas": [
            "405:395",
            0
          ],
          "latent_image": [
            "405:340",
            0
          ]
        },
        "class_type": "SamplerCustomAdvanced",
        "_meta": {
          "title": "SamplerCustomAdvanced"
        }
      },
      "405:338": {
        "inputs": {
          "noise_seed": 42
        },
        "class_type": "RandomNoise",
        "_meta": {
          "title": "RandomNoise"
        }
      },
      "405:367": {
        "inputs": {
          "av_latent": [
            "405:344",
            0
          ]
        },
        "class_type": "LTXVSeparateAVLatent",
        "_meta": {
          "title": "Separate AV Latent"
        }
      },
      "405:369": {
        "inputs": {
          "av_latent": [
            "405:368",
            0
          ]
        },
        "class_type": "LTXVSeparateAVLatent",
        "_meta": {
          "title": "Separate AV Latent"
        }
      },
      "405:374": {
        "inputs": {
          "tile_size": 512,
          "overlap": 64,
          "temporal_size": 64,
          "temporal_overlap": 16,
          "samples": [
            "405:369",
            0
          ],
          "vae": [
            "405:385",
            0
          ]
        },
        "class_type": "VAEDecodeTiled",
        "_meta": {
          "title": "VAE Decode (Tiled)"
        }
      },
      "405:344": {
        "inputs": {
          "noise": [
            "405:339",
            0
          ],
          "guider": [
            "405:388",
            0
          ],
          "sampler": [
            "405:352",
            0
          ],
          "sigmas": [
            "405:404",
            0
          ],
          "latent_image": [
            "405:377",
            0
          ]
        },
        "class_type": "SamplerCustomAdvanced",
        "_meta": {
          "title": "SamplerCustomAdvanced"
        }
      },
      "405:404": {
        "inputs": {
          "sigmas": "1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0"
        },
        "class_type": "ManualSigmas",
        "_meta": {
          "title": "ManualSigmas"
        }
      },
      "405:388": {
        "inputs": {
          "video_cfg": 1,
          "audio_cfg": 1,
          "model": [
            "405:384",
            0
          ],
          "positive": [
            "405:365",
            0
          ],
          "negative": [
            "405:365",
            1
          ]
        },
        "class_type": "LTXVDualCFGGuider",
        "_meta": {
          "title": "LTXV Dual CFG Guider"
        }
      },
      "405:352": {
        "inputs": {
          "sampler_name": "euler_ancestral"
        },
        "class_type": "KSamplerSelect",
        "_meta": {
          "title": "KSamplerSelect"
        }
      },
      "405:339": {
        "inputs": {
          "noise_seed": 375033649223599
        },
        "class_type": "RandomNoise",
        "_meta": {
          "title": "RandomNoise"
        }
      },
      "405:365": {
        "inputs": {
          "frame_rate": [
            "405:359",
            0
          ],
          "positive": [
            "405:364",
            0
          ],
          "negative": [
            "405:373",
            0
          ]
        },
        "class_type": "LTXVConditioning",
        "_meta": {
          "title": "LTXVConditioning"
        }
      },
      "405:377": {
        "inputs": {
          "video_latent": [
            "405:356",
            0
          ],
          "audio_latent": [
            "405:366",
            0
          ]
        },
        "class_type": "LTXVConcatAVLatent",
        "_meta": {
          "title": "Concat AV Latent"
        }
      },
      "405:364": {
        "inputs": {
          "text": [
            "405:382",
            0
          ],
          "clip": [
            "405:387",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "405:373": {
        "inputs": {
          "text": "",
          "clip": [
            "405:387",
            0
          ]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Prompt)"
        }
      },
      "405:356": {
        "inputs": {
          "width": [
            "405:353",
            1
          ],
          "height": [
            "405:355",
            1
          ],
          "length": [
            "405:378",
            1
          ],
          "batch_size": 1
        },
        "class_type": "EmptyLTXVLatentVideo",
        "_meta": {
          "title": "EmptyLTXVLatentVideo"
        }
      },
      "405:366": {
        "inputs": {
          "frames_number": [
            "405:378",
            1
          ],
          "frame_rate": [
            "405:359",
            1
          ],
          "batch_size": 1,
          "audio_vae": [
            "405:386",
            0
          ]
        },
        "class_type": "LTXVEmptyLatentAudio",
        "_meta": {
          "title": "LTXV Empty Latent Audio"
        }
      },
      "405:381": {
        "inputs": {
          "source": [
            "405:382",
            0
          ]
        },
        "class_type": "PreviewAny",
        "_meta": {
          "title": "Preview as Text"
        }
      },
      "405:382": {
        "inputs": {
          "switch": [
            "405:383",
            0
          ],
          "on_false": [
            "405:376",
            0
          ],
          "on_true": [
            "405:380",
            0
          ]
        },
        "class_type": "ComfySwitchNode",
        "_meta": {
          "title": "If/Else Switch"
        }
      },
      "405:371": {
        "inputs": {
          "model_name": "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
        },
        "class_type": "LatentUpscaleModelLoader",
        "_meta": {
          "title": "Load Latent Upscale Model"
        }
      },
      "405:384": {
        "inputs": {
          "unet_name": "ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors",
          "weight_dtype": "default"
        },
        "class_type": "UNETLoader",
        "_meta": {
          "title": "Load Diffusion Model"
        }
      },
      "405:385": {
        "inputs": {
          "vae_name": "ltx-2.5-video-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "405:386": {
        "inputs": {
          "vae_name": "ltx-2.5-audio-vae-bf16.safetensors"
        },
        "class_type": "VAELoader",
        "_meta": {
          "title": "Load VAE"
        }
      },
      "405:387": {
        "inputs": {
          "clip_name": "gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "405:380": {
        "inputs": {
          "prompt": [
            "405:376",
            0
          ],
          "max_length": 600,
          "sampling_mode": "on",
          "sampling_mode.temperature": 0.7,
          "sampling_mode.top_k": 64,
          "sampling_mode.top_p": 0.95,
          "sampling_mode.min_p": 0.05,
          "sampling_mode.repetition_penalty": 1.15,
          "sampling_mode.seed": 0,
          "sampling_mode.presence_penalty": 0,
          "thinking": false,
          "use_default_template": true,
          "clip": [
            "405:393",
            0
          ]
        },
        "class_type": "TextGenerateLTX2Prompt",
        "_meta": {
          "title": "Generate LTX2 Prompt"
        }
      },
      "405:378": {
        "inputs": {
          "expression": "a * b + 1",
          "values.a": [
            "405:362",
            0
          ],
          "values.b": [
            "405:361",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression (length)"
        }
      },
      "405:353": {
        "inputs": {
          "expression": "a/2",
          "values.a": [
            "405:372",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "405:355": {
        "inputs": {
          "expression": "a/2",
          "values.a": [
            "405:360",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression"
        }
      },
      "405:359": {
        "inputs": {
          "expression": "a",
          "values.a": [
            "405:361",
            0
          ]
        },
        "class_type": "ComfyMathExpression",
        "_meta": {
          "title": "Math Expression (fps)"
        }
      },
      "405:360": {
        "inputs": {
          "value": [
            "409",
            1
          ]
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Height"
        }
      },
      "405:361": {
        "inputs": {
          "value": 24
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Frame Rate"
        }
      },
      "405:362": {
        "inputs": {
          "value": 5
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Duration"
        }
      },
      "405:372": {
        "inputs": {
          "value": [
            "409",
            0
          ]
        },
        "class_type": "PrimitiveInt",
        "_meta": {
          "title": "Width"
        }
      },
      "405:376": {
        "inputs": {
          "value": "prompt text"
        },
        "class_type": "PrimitiveStringMultiline",
        "_meta": {
          "title": "Prompt"
        }
      },
      "405:393": {
        "inputs": {
          "clip_name": "gemma4_e2b_it_bf16.safetensors",
          "type": "ltxv",
          "device": "default"
        },
        "class_type": "CLIPLoader",
        "_meta": {
          "title": "Load CLIP"
        }
      },
      "405:383": {
        "inputs": {
          "value": true
        },
        "class_type": "PrimitiveBoolean",
        "_meta": {
          "title": "Boolean (Enable Prompt Enhance)"
        }
      }
    }
  comfy/workflows/video-ltx-first-last.yml: |
    # LTX-2.5 first-and-last-frame to video (with audio): input_image anchors the
    # first frame, last_image the final one. The message body is the prompt.
    #
    # This graph has no ResolutionSelector — width/height are the size knob, and
    # nothing quantizes them, so they are not aligned here either: the workflow ships
    # 1280x720 and 720 is not a multiple of 32. What you ask for is what it gets.
    workflow: video_ltx2_5_first_last.json
    params:
      prompt:
        required: true
        bind:
          - { node: "251:252", input: value }
      input_image:
        type: image
        required: true
        bind:
          - { node: "31", input: image }
      last_image:
        type: image
        required: true
        bind:
          - { node: "39", input: image }
      width:
        type: int
        bind:
          - { node: "251:215", input: value }
      height:
        type: int
        bind:
          - { node: "251:216", input: value }
      duration:
        type: int
        bind:
          - { node: "251:198", input: value }
      fps:
        type: int
        bind:
          - { node: "251:205", input: value }
      enhance_prompt:
        type: bool
        bind:
          - { node: "251:250", input: value }
      seed:
        type: int
        default: random
        bind:
          - { node: "251:196", input: noise_seed }
      output_prefix:
        required: true
        bind:
          - { node: "68", input: filename_prefix }
  comfy/workflows/video-ltx-image.yml: |
    # LTX-2.5 image-to-video (with audio): input_image is the first frame.
    # The message body is the prompt. Size comes from the ResolutionSelector, and a
    # width/height override replaces its link — see video-ltx-text.yml.
    workflow: video_ltx2_5_image.json
    params:
      prompt:
        required: true
        bind:
          - { node: "398:376", input: value }
      input_image:
        type: image
        required: true
        bind:
          - { node: "395", input: image }
      aspect_ratio:
        bind:
          - { node: "403", input: aspect_ratio }
      megapixels:
        type: float
        bind:
          - { node: "403", input: megapixels }
      multiple:
        type: int
        bind:
          - { node: "403", input: multiple }
      width:
        type: int
        align: 32
        bind:
          - { node: "398:372", input: value }
      height:
        type: int
        align: 32
        bind:
          - { node: "398:360", input: value }
      duration:
        type: int
        bind:
          - { node: "398:362", input: value }
      fps:
        type: int
        bind:
          - { node: "398:361", input: value }
      enhance_prompt:
        type: bool
        bind:
          - { node: "398:383", input: value }
      seed:
        type: int
        default: random
        bind:
          - { node: "398:339", input: noise_seed }
      output_prefix:
        required: true
        bind:
          - { node: "75", input: filename_prefix }
  comfy/workflows/video-ltx-text.yml: |
    # LTX-2.5 text-to-video (with audio). The message body is the prompt.
    #
    # Size comes from the ResolutionSelector, which is how the graph itself computes
    # it: pick an aspect_ratio and a megapixels budget. Setting width/height instead
    # replaces the selector's link with a literal — aligned to 32 so an override
    # lands on the same grid the selector's own `multiple` would have produced.
    workflow: video_ltx2_5_text.json
    params:
      prompt:
        required: true
        bind:
          - { node: "405:376", input: value }
      aspect_ratio:
        bind:
          - { node: "409", input: aspect_ratio }
      megapixels:
        type: float
        bind:
          - { node: "409", input: megapixels }
      multiple:
        type: int
        bind:
          - { node: "409", input: multiple }
      width:
        type: int
        align: 32
        bind:
          - { node: "405:372", input: value }
      height:
        type: int
        align: 32
        bind:
          - { node: "405:360", input: value }
      # Seconds, not frames — the graph derives the frame count from duration × fps.
      duration:
        type: int
        bind:
          - { node: "405:362", input: value }
      fps:
        type: int
        bind:
          - { node: "405:361", input: value }
      # Rewrites the prompt through a local LLM before encoding it.
      enhance_prompt:
        type: bool
        bind:
          - { node: "405:383", input: value }
      seed:
        type: int
        default: random
        bind:
          - { node: "405:339", input: noise_seed }
      output_prefix:
        required: true
        bind:
          - { node: "75", input: filename_prefix }
endpoints:
  # ComfyUI generation from anything that can POST. The body is the prompt;
  # everything else is a path parameter, because the body is never parsed.
  #
  #   curl -X POST https://automation-webhook.<domain>/comfy/image-text/sunset \
  #     -H "Authorization: Bearer <secret>" --data-binary 'a sunset over mountains'
  #
  # `type` names a workflow binding in lib/comfy/workflows/ (this plugin's lib); `name`
  # becomes the output filename prefix, under ComfyUI's output/comfy/.
  - path: /comfy/{type}/{name}
    patterns: {type: "[a-z0-9-]+", name: "[A-Za-z0-9_.-]+"}
    message:
      machine: comfy
      params: {type: "{{type}}", output_prefix: "comfy/{{name}}"}
  # The reference-image form. `image` is a filename ComfyUI already knows —
  # anything in its input/ folder. A path parameter cannot contain "/", so this
  # reaches only images sitting directly in input/.
  - path: /comfy/{type}/{name}/{image}
    patterns: {type: "[a-z0-9-]+", name: "[A-Za-z0-9_.-]+", image: "[A-Za-z0-9_.-]+"}
    message:
      machine: comfy
      params: {type: "{{type}}", output_prefix: "comfy/{{name}}", input_image: "{{image}}"}
  # The two-image form, for video-ltx-first-last: input_image anchors the first
  # frame, last_image the final one.
  - path: /comfy/{type}/{name}/{image}/{last}
    patterns: {type: "[a-z0-9-]+", name: "[A-Za-z0-9_.-]+", image: "[A-Za-z0-9_.-]+", last: "[A-Za-z0-9_.-]+"}
    message:
      machine: comfy
      params: {type: "{{type}}", output_prefix: "comfy/{{name}}", input_image: "{{image}}", last_image: "{{last}}"}
---
# comfy

Generate an image or video in ComfyUI from a workflow binding in lib/comfy/workflows/, the message body as the prompt.

It needs, on the stack that installs it:

- $DECREE_LIB/comfy
