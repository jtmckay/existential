# shellcheck shell=bash
# tmx — run a long-lived process in a named tmux session (.claude/reference/services.md).
#   tmx -d <name> [cmd]  start detached, only if <name> is not already running
#   tmx <name> [cmd]     attach, creating it if needed
# Sourced: the image installs it as /etc/profile.d/tmx.sh, so every login shell has it.
function tmx() {
    local detach=0
    if [ "$1" = "-d" ]; then
        detach=1
        shift
    fi
    local name="$1"
    shift
    local cmd="${*:-$name}"
    if [ "$detach" -eq 1 ]; then
        tmux has-session -t "=$name" 2>/dev/null || tmux new -d -s "$name" bash -ic "$cmd"
    else
        tmux new -A -s "$name" bash -ic "$cmd"
    fi
}
