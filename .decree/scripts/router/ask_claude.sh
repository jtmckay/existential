#!/usr/bin/env bash
# router's only script. Reads the request decree wrote, asks Claude,
# and writes the reply. Exits non-zero (and so runs once more, attempts: 2)
# unless the reply names one of the options. Replace this machine to use
# another model; decree validates the reply again either way.
set -euo pipefail
req="$DECREE_REQUEST"
prompt=$(jq -r '
  "You choose the next step of a workflow. Reply with only a JSON object:\n" +
  "{\"event\": \"<one option name>\", \"reason\": \"<one sentence>\", \"confidence\": <0 to 1>}\n\n" +
  "Workflow: \(.machine): \(.machine_description)\n" +
  "Current step: \(.state): \(.state_description)\n" +
  "Question: \(.question)\n\n" +
  "Output this decision reads (empty if none):\n\(.input)\n\n" +
  "Task message:\n\(.message_body)\n\n" +
  "Run so far:\n\(.history | map("- " + .) | join("\n"))\n\n" +
  "Options:\n\(.options | map("- \(.event): \(.description)") | join("\n"))"' "$req")
echo "$prompt"
echo "--- reply"
reply=$(printf '%s' "$prompt" | claude -p)
echo "$reply"
# the last JSON object in the reply, fences and prose around it allowed: the last
# fenced block (which may span lines) if there is one, else the last line holding one
fenced=$(printf '%s\n' "$reply" | awk '
  /^[[:space:]]*```/ { if (inside) { last = block; inside = 0 } else { inside = 1; block = "" }; next }
  inside { block = block $0 " " }
  END { printf "%s", last }')
json=$(printf '%s\n' "${fenced:-$reply}" | grep -o '{.*}' | tail -n 1 || true)
json=$(jq -c . <<<"$json" 2>/dev/null) || { echo "no JSON object in the reply" >&2; exit 1; }
event=$(jq -r '.event | strings' <<<"$json")
jq -e --arg e "$event" '.options | map(.event) | index($e)' "$req" > /dev/null \
  || { echo "not an option: $event" >&2; exit 1; }
printf '%s\n' "$json" > "$DECREE_REPLY"
# for the log only: decree takes the event from the reply
echo "picked $event"
