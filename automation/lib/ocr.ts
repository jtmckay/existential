// OCR an image file via a vision model behind an OpenAI-compatible /v1 endpoint
// (ollama, llama.cpp with a projector, anything that takes image_url content).
// Works as a reusable library function OR as a standalone entry point when called
// directly by tsx (reads FILE_PATH, OCR_MODEL, MODEL_URL from env, writes text to stdout).
// Callers resolve MODEL_URL with lib/model.sh's `model_url vision`.

import { readFileSync } from "node:fs";
import { extname } from "node:path";

interface ChatCompletionResponse {
  choices?: { message?: { content?: string } }[];
}

export interface OcrOptions {
  model?: string;
  modelUrl?: string;
  prompt?: string;
}

// The vision model is chosen ONCE, globally, in .env.exist.shared's Model
// Selection block and reaches this container as EXIST_MODEL_VISION.
//
// There is deliberately no hardcoded fallback. The default here used to be
// "llava", which no migration and no routine ever pulls, so every OCR call
// 404'd on a stock install — silently, because the caller reported only "OCR
// failed". Failing loudly with the fix in the message beats guessing a tag.
function visionModel(): string {
  const model = process.env.OCR_MODEL || process.env.EXIST_MODEL_VISION;
  if (!model) {
    throw new Error(
      "No vision model configured: set EXIST_MODEL_VISION in .env.shared " +
        "(chosen from the VRAM tier table — see .claude/reference/models.md).",
    );
  }
  return model;
}

function modelUrl(): string {
  const url = process.env.MODEL_URL;
  if (!url) throw new Error("MODEL_URL is required — resolve it with `model_url vision` (lib/model.sh)");
  return url;
}

const MIME: Record<string, string> = {
  ".png": "image/png",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".bmp": "image/bmp",
  ".tif": "image/tiff",
  ".tiff": "image/tiff",
  ".heic": "image/heic",
  ".heif": "image/heif",
};

export async function ocr(filePath: string, options: OcrOptions = {}): Promise<string> {
  const {
    model = visionModel(),
    modelUrl: url = modelUrl(),
    prompt = "Extract all text from this image exactly as it appears. Preserve the original formatting and line breaks. If there is no text, respond with 'No text found.'",
  } = options;

  const mime = MIME[extname(filePath).toLowerCase()] ?? "image/jpeg";
  const image = `data:${mime};base64,${readFileSync(filePath).toString("base64")}`;

  const res = await fetch(`${url.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: image } },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Model error (${res.status}): ${body}`);
  }

  const data = (await res.json()) as ChatCompletionResponse;
  return data.choices?.[0]?.message?.content ?? "";
}

if (require.main === module) {
  const filePath = process.env.FILE_PATH ?? "";
  // Prompt can be passed as argv[2] or omitted to use the default inside ocr()
  const prompt = process.argv[2] || undefined;

  if (!filePath) {
    console.error("FILE_PATH is required");
    process.exit(1);
  }

  ocr(filePath, { prompt })
    .then((text) => process.stdout.write(text))
    .catch((err: Error) => {
      console.error(err.message);
      process.exit(1);
    });
}
