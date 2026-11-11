---
machine: plugin
automation: capture
chart:
  description: Append the message body (JSON {source, text} or plain text) to the capture stream, workspace/.capture/.
  data:
    source: {type: string, default: webhook}
  initial: append
  states:
    append:
      invoke: capture
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  capture: |
    #!/usr/bin/env bash
    # Capture
    #
    # Appends the message body to workspace/.capture/ through lib/capture/capture.sh,
    # the same redaction and stream code-server's Claude Code and opencode write to.
    # automation-webhook's POST /capture queues it:
    #
    #   curl -X POST https://automation-webhook.<domain>/capture \
    #     -H "Authorization: Bearer <secret>" -d '{"source":"phone","text":"buy filters"}'
    #
    # A JSON body's `source` wins over the param; a plain-text body is the text.
    set -euo pipefail

    body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE")

    # Waits, unlike the hooks, so this run's log holds the write and any failure.
    CAPTURE_DIR="${CAPTURE_DIR:-/workspace/.capture}" CAPTURE_HOST=automation CAPTURE_WAIT=1 \
        bash "${DECREE_LIB}/capture/capture.sh" "${DECREE_DATA_SOURCE:-webhook}" <<<"$body"
lib:
  capture/capture.sh: |
    #!/usr/bin/env bash
    # capture.sh — append what a person typed to the capture stream, workspace/.capture/.
    #
    #   capture.sh <source>               JSON on stdin: {prompt|text, cwd|context, session_id|session, source?}
    #                                     (a Claude Code UserPromptSubmit hook's input as-is);
    #                                     anything that is not a JSON object is the text itself.
    #   capture.sh install <workspace>    add the Claude Code hook to this machine's settings
    #   capture.sh uninstall              remove it
    #
    # One JSON line per capture — {ts, source, context, session, text} — in
    # $CAPTURE_DIR/<YYYY-MM>-<CAPTURE_HOST>.jsonl: one file per writer, so two machines
    # syncing the workspace never edit the same file. Secrets of common shapes are
    # replaced by [REDACTED:<kind>] before anything is written. A prompt with a
    # session id (an AI CLI's) is also appended, as Markdown, to
    # $CAPTURE_MD_DIR (default: ai/conversations/ beside $CAPTURE_DIR), where search
    # indexes it.
    #
    # Never blocks and never fails its caller: the write runs detached (CAPTURE_WAIT=1
    # waits, for a decree run that should reflect it), always exits 0, and a failure
    # goes to $CAPTURE_DIR/errors.log and stderr. Needs bash and jq, nothing else.
    set -uo pipefail

    CAPTURE_HOST="${CAPTURE_HOST:-${HOSTNAME:-$(uname -n)}}"

    # Applied in order: a key whose shape is known first, so its marker is the most
    # specific one; the assignment rule skips a value already redacted.
    # shellcheck disable=SC2016  # jq, not shell
    JQ_PROGRAM='
    def redact:
      gsub("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"; "[REDACTED:private-key]")
      | gsub("sk-ant-[^\\s\"'"'"'`]+"; "[REDACTED:anthropic-key]")
      | gsub("sk-[A-Za-z0-9_-]{20,}"; "[REDACTED:openai-key]")
      | gsub("gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"; "[REDACTED:github-token]")
      | gsub("AKIA[0-9A-Z]{16}"; "[REDACTED:aws-key]")
      | gsub("xox[abposr]-[A-Za-z0-9-]{10,}"; "[REDACTED:slack-token]")
      | gsub("AIza[0-9A-Za-z_-]{35}"; "[REDACTED:google-key]")
      | gsub("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"; "[REDACTED:jwt]")
      | gsub("(?<k>[Bb]earer)\\s+[A-Za-z0-9._~+/=-]{16,}"; "\(.k) [REDACTED:bearer-token]")
      | gsub("(?<k>(?i)\\b[a-z_]*(?:password|passwd|secret|token|api[_-]?key)[a-z_]*)(?<s>[\"'"'"']?\\s*[=:]\\s*)(?!\\[REDACTED)(?<v>\"[^\"]*\"|'"'"'[^'"'"']*'"'"'|[^\\s\"'"'"']+)";
             "\(.k)\(.s)[REDACTED:\(.k | ascii_downcase)]");
    (try fromjson catch null) as $j
    | (if ($j | type) == "object" then $j else {text: sub("\\s+$"; "")} end)
    | ((.prompt // .text // "") | tostring) as $text
    | if ($text | test("^\\s*$")) then empty else
        {ts: $ts, source: ((.source // $source) | tostring),
         context: ((.context // .cwd) | if . == null then null else tostring | redact end),
         session: ((.session_id // .session) | if . == null then null else tostring end),
         text: ($text | redact)}
      end'

    _append() {             # <source> <input>
        local line
        line="$(jq -Rsc --arg source "$1" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$JQ_PROGRAM" <<<"$2")" || return 1
        [[ -n "$line" ]] || return 0
        printf '%s\n' "$line" >> "${CAPTURE_DIR}/$(date -u +%Y-%m)-${CAPTURE_HOST}.jsonl"
        _markdown "$line"
    }

    # A prompt typed into an AI CLI (it has a session id) is also appended to that
    # session's Markdown, one file per session per day, so search finds it beside
    # the notes. Each prompt is a blockquote under its timestamp, so a heading in it
    # stays text, and the file says these are questions, not decisions.
    # shellcheck disable=SC2016  # jq, not shell
    _markdown() {           # <capture line>
        local dir name
        [[ "$(jq -r '.session // empty' <<<"$1")" ]] || return 0
        dir="${CAPTURE_MD_DIR:-$(dirname "$CAPTURE_DIR")/ai/conversations}"
        name="$(jq -r '"\(.ts[0:10])-\(.source)-\(.session[0:8])"' <<<"$1" | tr -c 'A-Za-z0-9._\n-' '-')"
        mkdir -p "$dir"
        [[ -f "$dir/$name.md" ]] || jq -r '"---\nkind: conversation\nsource: \(.source | tojson)\nsession: \(.session | tojson)\ndate: \(.ts[0:10])\ncontext: \(.context | tojson)\n---\n\n# Prompts typed into \(.source) on \(.ts[0:10])\n\nWhat the person asked, as typed (secrets redacted). The AI'"'"'s answers are not kept. These are questions and ideas from the moment, not decisions."' \
            <<<"$1" > "$dir/$name.md"
        jq -r '"\n## \(.ts)\n\n" + (.text | split("\n") | map("> " + .) | join("\n"))' <<<"$1" >> "$dir/$name.md"
    }

    _capture() {            # <source> <input>
        local err
        if ! err="$({ mkdir -p "$CAPTURE_DIR" && _append "$1" "$2"; } 2>&1)" || [[ -n "$err" ]]; then
            err="$(date -u +%Y-%m-%dT%H:%M:%SZ) capture failed (${1}): ${err:-no detail}"
            printf '%s\n' "$err" >> "${CAPTURE_DIR}/errors.log" 2>/dev/null
            printf '%s\n' "$err" >&2
        fi
    }

    # Claude Code reads hooks from settings.json in its config dir. Ours is the one
    # whose command runs this script for claude-code; nothing else there is touched.
    _settings() { printf '%s/settings.json' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
    # shellcheck disable=SC2016  # jq, not shell
    _UNHOOK='(.hooks.UserPromptSubmit // [])
        |= map(.hooks |= map(select(.command | test("capture\\.sh. claude-code") | not))
               | select(.hooks | length > 0))
      | if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end
      | if .hooks == {} then del(.hooks) else . end'

    _edit_settings() {      # <jq filter> [--arg k v]...
        local f tmp
        f="$(_settings)"; tmp="${f}.capture.tmp"
        mkdir -p "$(dirname "$f")"
        [[ -s "$f" ]] || echo '{}' > "$f"
        jq "${@:2}" "$1" "$f" > "$tmp" && mv "$tmp" "$f"
    }

    case "${1:-}" in
        install)
            [[ -d "${2:-}" ]] || { echo "usage: capture.sh install <workspace dir>" >&2; exit 1; }
            dir="$(cd "$2" && pwd)/.capture"
            self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
            _edit_settings "${_UNHOOK} | .hooks.UserPromptSubmit += [{hooks: [{type: \"command\", command: \$cmd}]}]" \
                --arg cmd "CAPTURE_DIR='${dir}' bash '${self}' claude-code"
            echo "Claude Code prompts are captured to ${dir} ($(_settings))."
            ;;
        uninstall)
            [[ -f "$(_settings)" ]] && _edit_settings "$_UNHOOK"
            echo "Claude Code prompts are no longer captured ($(_settings))."
            ;;
        "")
            echo "usage: capture.sh <source> | install <workspace dir> | uninstall" >&2
            exit 1
            ;;
        *)
            [[ -n "${CAPTURE_DIR:-}" ]] || { echo "capture.sh: CAPTURE_DIR is not set" >&2; exit 0; }
            input="$(cat)"
            if [[ "${CAPTURE_WAIT:-}" == 1 ]]; then
                _capture "$1" "$input"
            else
                _capture "$1" "$input" </dev/null >/dev/null 2>&1 &
            fi
            ;;
    esac
    exit 0
  capture/opencode.ts: |
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
      'chat.message': async (input: { sessionID?: string }, output: { parts: Part[] }) => {
        const prompt = output.parts
          .filter((p) => p.type === 'text' && !p.synthetic && !p.ignored)
          .map((p) => p.text ?? '')
          .join('\n');
        if (!prompt.trim()) return;
        try {
          const child = spawn('bash', [SCRIPT, 'opencode'], { stdio: ['pipe', 'ignore', 'ignore'] });
          child.on('error', (e) => console.error(`capture: ${e.message}`));
          child.stdin.on('error', (e) => console.error(`capture: ${e.message}`));
          child.stdin.end(JSON.stringify({ prompt, cwd: directory, session_id: input.sessionID }));
        } catch (e) {
          console.error(`capture: ${String(e)}`);
        }
      },
    });
endpoints:
  # The capture stream, workspace/.capture/: a phone shortcut or any tool adds a
  # line. The body is {"source": "...", "text": "..."} or plain text. Delete this
  # entry, or `./existential.sh run plugin off capture`, to turn webhook capture off.
  - path: /capture
    message:
      machine: capture
---
# capture

Append the message body (JSON {source, text} or plain text) to the capture stream, workspace/.capture/.

It needs, on the stack that installs it:

- $DECREE_LIB/capture/capture.sh
