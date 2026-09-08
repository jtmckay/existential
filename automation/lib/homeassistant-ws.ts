// Run a single command against Home Assistant's websocket API and print the
// result as JSON. Some HA APIs (assist_pipeline's pipeline create/update/
// set_preferred among them) are websocket-only — no REST equivalent — so this
// is the one place decree needs a websocket client at all.
//
// Works as a reusable library function OR as a standalone entry point when
// called directly by tsx (reads HA_WS_URL, HA_WS_TOKEN, HA_WS_COMMAND from
// env — the last a JSON object with at least a "type" field — and writes the
// command's `result` to stdout as JSON).

export function runWsCommand(url: string, token: string, command: Record<string, unknown>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let id = 1;
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error("timed out waiting for a response"));
    }, 15000);

    ws.addEventListener("message", (ev: MessageEvent) => {
      const msg = JSON.parse(ev.data as string);
      if (msg.type === "auth_required") {
        ws.send(JSON.stringify({ type: "auth", access_token: token }));
      } else if (msg.type === "auth_invalid") {
        clearTimeout(timeout);
        ws.close();
        reject(new Error(`auth_invalid: ${msg.message ?? ""}`));
      } else if (msg.type === "auth_ok") {
        ws.send(JSON.stringify({ id: id++, ...command }));
      } else if (msg.type === "result") {
        clearTimeout(timeout);
        ws.close();
        if (msg.success) {
          resolve(msg.result);
        } else {
          reject(new Error(`${msg.error?.code ?? "error"}: ${msg.error?.message ?? JSON.stringify(msg)}`));
        }
      }
    });
    ws.addEventListener("error", (ev: Event) => {
      clearTimeout(timeout);
      reject(new Error(`websocket error: ${(ev as ErrorEvent).message ?? "unknown"}`));
    });
  });
}

if (require.main === module) {
  const url = process.env.HA_WS_URL ?? "";
  const token = process.env.HA_WS_TOKEN ?? "";
  const commandJson = process.env.HA_WS_COMMAND ?? "";
  if (!url || !token || !commandJson) {
    console.error("HA_WS_URL, HA_WS_TOKEN and HA_WS_COMMAND are required");
    process.exit(1);
  }

  runWsCommand(url, token, JSON.parse(commandJson))
    .then((result) => {
      process.stdout.write(JSON.stringify(result) + "\n");
    })
    .catch((err: Error) => {
      console.error(err.message);
      process.exit(1);
    });
}
