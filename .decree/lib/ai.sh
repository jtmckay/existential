# The AI helper the built-in machines' scripts source: `. "$DECREE_LIB/ai.sh"`,
# then `ai "<prompt>"` asks the AI and prints its reply.
#
# Every backend is a function here: ai_claude, ai_opencode, ai_copilot. `ai` calls,
# most specific first: the one the run's data entry `ai_cli` names
# (DECREE_DATA_AI_CLI: a message's or a parent's `params`, else the machine's
# default), so a child machine invoked with `params: { ai_cli: claude }` works with
# Claude whatever the project's setting; else the one AI_CLI names (in .decree/.env,
# or the shell decree runs in); else claude, which `decree init --ai` chose. To use another
# backend, add an ai_<name> function and set AI_CLI=<name>.
#
# The agent names no event (it writes STOP instead): a script it runs, such as the
# gate, gets DECREE_EVENT_FILE=/dev/null, and the caller's event file is emptied
# after the call, in case the agent found its path anyway. A call that leaves a STOP
# file in the root run's folder ($DECREE_ROOT_RUN_DIR) returns 0 whatever the
# backend's exit code, so the caller's STOP check names `stop` instead of failing
# an attempt.
#
# Every call adds a line to .decree/ai-use.md (git ignores it): when, which run and
# state, which CLI and model, the run's attempt and the step's, how long it took
# and its exit code.
AI_DEFAULT=claude

ai() {
  local cli=${DECREE_DATA_AI_CLI:-${AI_CLI:-${AI_DEFAULT}}}
  if ! declare -F "ai_${cli}" >/dev/null; then
    echo "ai: no ai_${cli} function in lib/ai.sh (AI_CLI=${cli})" >&2
    return 2
  fi
  local caller_event=${DECREE_EVENT_FILE:-} status=0 start=${SECONDS}
  local -x DECREE_EVENT_FILE=/dev/null
  "ai_${cli}" "$1" || status=$?
  [ -z "${caller_event}" ] || : > "${caller_event}"
  ai_log "${cli}" "$((SECONDS - start))" "${status}" || true
  [ ! -f "${DECREE_ROOT_RUN_DIR:-${DECREE_RUN_DIR:-.}}/STOP" ] || status=0
  return "${status}"
}

# One line in .decree/ai-use.md, its table header first. Past 2 MiB it keeps the
# header and the last 10000 calls.
ai_log() {
  local log="${DECREE_PROJECT_ROOT:-.}/.decree/ai-use.md" model
  [ -d "${log%/*}" ] || return 0
  case $1 in
    claude) model=${CLAUDE_MODEL:-default} ;;
    opencode) model=${OPENCODE_MODEL:-default} ;;
    *) model=default ;;
  esac
  if [ ! -s "${log}" ]; then
    printf '| time | run | state | cli | model | run attempt | attempt | seconds | exit |\n' > "${log}"
    printf '| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n' >> "${log}"
  fi
  printf '| %s | %s | %s/%s | %s | %s | %s | %s | %s | %s |\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${DECREE_MESSAGE_ID:-}" "${DECREE_MACHINE:-}" \
    "${DECREE_STATE:-}" "$1" "${model}" "${DECREE_RUN_ATTEMPT:-1}" "${DECREE_ATTEMPT:-1}" \
    "$2" "$3" >> "${log}"
  if [ "$(wc -c < "${log}")" -gt 2097152 ]; then
    { head -n 2 "${log}"; tail -n 10000 "${log}"; } > "${log}.tmp" && mv "${log}.tmp" "${log}"
  fi
}

# --- Claude ---------------------------------------------------------------------
# Each call is a new session, listed in the run's sessions.txt with its transcript,
# which Claude writes as it goes and keeps even if the session dies.
# When Claude stops at its usage limit (its output names a "usage limit" and a
# "reset"), wait until the reset time it names, or an hour if it names none, then
# resume the same session with the same prompt: the work it did is kept, and the
# wait uses none of the step's attempts. A reset further away than AI_LIMIT_WAIT
# (default 6h; s, m, h or d) is not waited for: the call writes STOP saying when to
# retry, so the run stops instead of sleeping through a weekly limit.
# CLAUDE_PERMISSION_MODE is passed to every call, so the run does not inherit your
# interactive default (in `plan` mode Claude can only plan, and changes nothing). `auto`
# approves what Claude's classifier judges safe; `acceptEdits` approves only file edits.
# CLAUDE_MODEL, if set (haiku, sonnet, a full model id), picks the model for every call.
CLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-auto}"
AI_LIMIT_WAIT="${AI_LIMIT_WAIT:-6h}"
ai_claude() {
  local prompt=$1 session out status wait
  session=$(new_session_id)
  echo "=== claude session ${session} ===" >&2
  echo "${DECREE_STATE} ${session} ${HOME}/.claude/projects/$(pwd | sed 's/[^A-Za-z0-9]/-/g')/${session}.jsonl" \
    >> "${DECREE_RUN_DIR}/sessions.txt"
  local session_flag=(--session-id "${session}")
  while true; do
    out=$(mktemp)
    # stdout to stdout and stderr to stderr, both also kept in $out
    if { claude -p --permission-mode "${CLAUDE_PERMISSION_MODE}" ${CLAUDE_MODEL:+--model "${CLAUDE_MODEL}"} "${session_flag[@]}" "${prompt}" 2>&1 1>&3 3>&- | tee -a "${out}" >&2; } 3>&1 | tee -a "${out}"; then
      status=0
    else
      status=$?
    fi
    if [ "${status}" -eq 0 ] || ! usage_limit "${out}"; then
      rm -f "${out}"
      return "${status}"
    fi
    wait=$(seconds_until_reset "${out}")
    rm -f "${out}"
    if [ "${wait}" -gt "$(seconds_of "${AI_LIMIT_WAIT}")" ]; then
      echo "[Claude token limit] Usage limit reached; it resets $(reset_note "${wait}" ""), more than AI_LIMIT_WAIT (${AI_LIMIT_WAIT}) away. Wrote STOP." >&2
      {
        echo "Claude's usage limit is reached and resets $(reset_note "${wait}" "")."
        echo "That is more than AI_LIMIT_WAIT (${AI_LIMIT_WAIT}) away, so the run stopped instead of waiting."
        echo "After the reset, delete this file and run \`decree process --retry ${DECREE_MESSAGE_ID:-<id>}\`."
      } > "${DECREE_ROOT_RUN_DIR:-${DECREE_RUN_DIR}}/STOP"
      return 1
    fi
    reset_note "${wait}" "Usage limit reached." >&2
    sleep "${wait}"
    echo "[Claude token limit] Resuming session ${session}" >&2
    session_flag=(--resume "${session}")
  done
}

# A random version 4 UUID, the form `claude --session-id` takes.
new_session_id() {
  printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x\n' "${RANDOM}" "${RANDOM}" "${RANDOM}" \
    $((RANDOM & 0xfff)) $((RANDOM & 0x3fff | 0x8000)) "${RANDOM}" "${RANDOM}" "${RANDOM}"
}

# Claude's wording varies: "usage limit reached … reset at 10:00 PM", "You've hit
# your session limit · resets 1:10am (America/Denver)", weekly and 5-hour limits.
usage_limit() {
  grep -qiE '(usage|session|weekly|daily|5-hour) limit|limit (reached|hit)' "$1" && grep -qi 'reset' "$1"
}

# Seconds until the time in "Limits reset at 10:00 PM" (local time, tomorrow if it
# has passed today), or 3600 if there is no such time.
seconds_until_reset() {
  local at h m now_h now_m now_s now wait=3600
  # "reset at 10:00 pm", "resets 1:10am", "resets 3am": read as local time.
  at=$(tr '[:upper:]' '[:lower:]' < "$1" | grep -oE 'resets?( +at)? +[0-9]{1,2}(:[0-9]{2})? *[ap]m' \
    | head -n 1 | grep -oE '[0-9]{1,2}(:[0-9]{2})? *[ap]m') || true
  IFS=: read -r now_h now_m now_s <<< "$(date +%H:%M:%S)"
  now=$((10#${now_h} * 3600 + 10#${now_m} * 60 + 10#${now_s}))
  if [ -n "${at}" ]; then
    h=${at%%[!0-9]*}
    h=$((10#${h}))
    m=0
    case ${at} in *:*) m=${at#*:}; m=$((10#${m:0:2})) ;; esac
    if [ "${h}" -le 12 ] && [ "${m}" -le 59 ]; then
      h=$((h % 12))
      case ${at} in *pm) h=$((h + 12)) ;; esac
      wait=$((h * 3600 + m * 60 - now))
      [ "${wait}" -gt 0 ] || wait=$((wait + 86400))
    fi
  fi
  echo "${wait}"
}

# "[Claude token limit] <what> Waiting until 22:00 (30m 0s) to retry." for a wait of
# $1 seconds; with an empty <what>, just "at 22:00 (in 30m 0s)".
reset_note() {
  local now_h now_m now_s now at
  IFS=: read -r now_h now_m now_s <<< "$(date +%H:%M:%S)"
  now=$((10#${now_h} * 3600 + 10#${now_m} * 60 + 10#${now_s}))
  at=$(((now + $1) % 86400))
  if [ -z "$2" ]; then
    printf 'at %02d:%02d (in %dm %ds)' $((at / 3600)) $((at % 3600 / 60)) $(($1 / 60)) $(($1 % 60))
  else
    printf '[Claude token limit] %s Waiting until %02d:%02d (%dm %ds) to retry.\n' \
      "$2" $((at / 3600)) $((at % 3600 / 60)) $(($1 / 60)) $(($1 % 60))
  fi
}

# `90`, `90s`, `10m`, `6h` or `1d` in seconds.
seconds_of() {
  local n=${1%[smhd]}
  case $1 in
    *m) echo $((n * 60)) ;;
    *h) echo $((n * 3600)) ;;
    *d) echo $((n * 86400)) ;;
    *) echo "${n}" ;;
  esac
}

# --- OpenCode -------------------------------------------------------------------
# OPENCODE_MODEL, if set (provider/model, e.g. llama.cpp/qwen3), picks the model.
# OpenCode's file tools ask before touching a path outside the project, and `opencode
# run` cannot answer, so with its default `"external_directory": "ask"` it rejects
# the call and ends the session with no reply (exit 0). `decree init --permissions`
# sets it to "deny", which rejects the call but lets the session go on. When a reject
# ends the session anyway, the call continues it (`opencode run -c`) up to AI_NUDGES
# times (default 2), telling the agent where scratch files go. The permission covers
# OpenCode's file tools only, not shell commands: it is no sandbox, and the prompt is
# what keeps writes in the project. The last call's output stays in the run folder,
# as opencode.out.
AI_NUDGES="${AI_NUDGES:-2}"
ai_opencode() {
  local out="${DECREE_RUN_DIR}/opencode.out" nudge=0 status=0
  local model=()
  [ -z "${OPENCODE_MODEL:-}" ] || model=(-m "${OPENCODE_MODEL}")
  opencode_call "${out}" "${model[@]}" "$1" || status=$?
  while grep -q 'permission requested: .*auto-rejecting' "${out}" && [ "${nudge}" -lt "${AI_NUDGES}" ]; do
    nudge=$((nudge + 1))
    echo "=== opencode: a tool call was rejected; continuing the session (${nudge}/${AI_NUDGES}) ===" >&2
    status=0
    opencode_call "${out}" -c "${model[@]}" "A tool call you made was rejected because it \
used a path outside the project, such as /tmp. Write scratch files only under \
${DECREE_RUN_DIR}. Continue the task from where you stopped and finish it exactly as \
the first instructions say, including how to end your reply." || status=$?
  done
  return "${status}"
}

# `opencode run <args>`, its stdout to stdout and stderr to stderr, both also in $1.
opencode_call() {
  local out=$1
  shift
  : > "${out}"
  { opencode run "$@" 2>&1 1>&3 3>&- | tee -a "${out}" >&2; } 3>&1 | tee -a "${out}"
}

# --- Copilot --------------------------------------------------------------------
ai_copilot() {
  copilot -p "$1"
}
