// OCR an image file via an Ollama vision model.
// Works as a reusable library function OR as a standalone entry point when called
// directly by tsx (reads FILE_PATH, OCR_MODEL, OLLAMA_URL from env, writes text to stdout).

import { readFileSync } from "node:fs";

interface OllamaGenerateResponse {
  response: string;
  done: boolean;
}

export interface OcrOptions {
  model?: string;
  ollamaUrl?: string;
  prompt?: string;
}

// The vision model is chosen ONCE, globally, in .env.exist.shared's Model
// Selection block and reaches this container as EXIST_MODEL_VISION; ollama
// migration 14-ollama-pull-vision-model.md is what pulls it.
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

export async function ocr(filePath: string, options: OcrOptions = {}): Promise<string> {
  const {
    model = visionModel(),
    ollamaUrl = process.env.OLLAMA_URL ?? "http://ollama:11434",
    prompt = "Extract all text from this image exactly as it appears. Preserve the original formatting and line breaks. If there is no text, respond with 'No text found.'",
  } = options;

  const base64 = readFileSync(filePath).toString("base64");

  const res = await fetch(`${ollamaUrl}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model, prompt, images: [base64], stream: false }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Ollama error (${res.status}): ${body}`);
  }

  const data = (await res.json()) as OllamaGenerateResponse;
  return data.response;
}

if (require.main === module) {
  const filePath = process.env.FILE_PATH ?? "";
  const model = visionModel();
  const ollamaUrl = process.env.OLLAMA_URL ?? "http://ollama:11434";
  // Prompt can be passed as argv[2] or omitted to use the default inside ocr()
  const prompt = process.argv[2] || undefined;

  if (!filePath) {
    console.error("FILE_PATH is required");
    process.exit(1);
  }

  ocr(filePath, { model, ollamaUrl, prompt })
    .then((text) => process.stdout.write(text))
    .catch((err: Error) => {
      console.error(err.message);
      process.exit(1);
    });
}
