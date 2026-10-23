// capture — opencode plugin. Every message typed into opencode goes through
// capture.sh beside it: the same redaction and the same stream as Claude Code's
// hook. Only the person's own text parts; the ones opencode adds itself
// (synthetic: attached file contents, tool context) are left out.
//
// Loaded from the `plugin` list entrypoint.sh writes into opencode's config, so
// it has no dependencies. Fire-and-forget: capture.sh detaches its own write.
import { spawn } from 'node:child_process';
import { join } from 'node:path';

// opencode runs plugins on Bun, which defines __dirname in ES modules too.
const SCRIPT = join(__dirname, 'capture.sh');

type Part = { type: string; text?: string; synthetic?: boolean; ignored?: boolean };

export const Capture = async ({ directory }: { directory: string }) => ({
  'chat.message': async (_input: unknown, output: { parts: Part[] }) => {
    const prompt = output.parts
      .filter((p) => p.type === 'text' && !p.synthetic && !p.ignored)
      .map((p) => p.text ?? '')
      .join('\n');
    if (!prompt.trim()) return;
    try {
      const child = spawn('bash', [SCRIPT, 'opencode'], { stdio: ['pipe', 'ignore', 'ignore'] });
      child.on('error', (e) => console.error(`capture: ${e.message}`));
      child.stdin.on('error', (e) => console.error(`capture: ${e.message}`));
      child.stdin.end(JSON.stringify({ prompt, cwd: directory }));
    } catch (e) {
      console.error(`capture: ${String(e)}`);
    }
  },
});
