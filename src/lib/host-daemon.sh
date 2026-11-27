#!/usr/bin/env bash
# host-daemon — the host's decree daemon (the repo's own .decree), started now and at every boot.
#   ./existential.sh run host-daemon install     start it, and at boot: a systemd user unit (Linux)
#                                                or a LaunchAgent (macOS), plus linger on Linux
#   ./existential.sh run host-daemon status      is it running, does it start at boot, what it last did
#   ./existential.sh run host-daemon uninstall   stop starting it at boot (the running daemon stays)
# The daemon is a tmux session, existential-host (tmux attach -t existential-host to watch it);
# what starts it at boot only starts that session, and leaves one that already runs alone.
# Runs on the host, a Mac included: bash 3.2, BSD tools. Running install twice changes nothing.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION=existential-host
UNIT="${HOME}/.config/systemd/user/${SESSION}.service"
PLIST="${HOME}/Library/LaunchAgents/company.existential.host.plist"
ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; }
note() { echo "  ⚠  $*"; }

running() { tmux has-session -t "=${SESSION}" 2>/dev/null; }

# Where decree, tmux, git and docker are: neither systemd nor launchd reads your shell's PATH.
path_line() {
    local p="${HOME}/.local/bin" t d
    for t in decree tmux git docker podman; do
        d="$(dirname "$(command -v "$t" 2>/dev/null || echo /usr/bin/x)")"
        case "$d" in /*) ;; *) continue ;; esac
        case ":${p}:" in *":${d}:"*) ;; *) p="${p}:${d}" ;; esac
    done
    echo "${p}:/usr/local/bin:/usr/bin:/bin"
}

needs() {
    local miss=0 t
    for t in decree tmux; do
        command -v "$t" >/dev/null 2>&1 || { bad "${t} is not here: ./existential.sh offers to install it"; miss=1; }
    done
    return "$miss"
}

start_now() {
    if running; then ok "running now (tmux attach -t ${SESSION})"; return 0; fi
    tmux new -d -s "$SESSION" -c "$REPO_DIR" "exec decree daemon"
    ok "started now (tmux attach -t ${SESSION})"
}

install_systemd() {
    local tmux_bin me
    tmux_bin="$(command -v tmux)"
    me="$(id -un)"
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<UNIT
# Written by ./existential.sh run host-daemon install; run it again after moving the checkout.
[Unit]
Description=existential host decree daemon (${REPO_DIR})

[Service]
# The daemon lives in a tmux session, which outlives this unit: oneshot, and KillMode=process,
# so stopping the unit ends that session and no other.
Type=oneshot
RemainAfterExit=yes
KillMode=process
WorkingDirectory=${REPO_DIR}
Environment=PATH=$(path_line)
ExecStart=/bin/sh -c '${tmux_bin} has-session -t =${SESSION} 2>/dev/null || exec ${tmux_bin} new -d -s ${SESSION} "exec decree daemon"'
ExecStop=${tmux_bin} kill-session -t ${SESSION}

[Install]
WantedBy=default.target
UNIT
    ok "wrote ${UNIT/#$HOME/~}"
    systemctl --user daemon-reload
    systemctl --user enable --now "${SESSION}.service" >/dev/null 2>&1 \
        && ok "starts at boot (systemctl --user status ${SESSION})" \
        || { bad "systemctl --user enable --now ${SESSION} failed: systemctl --user status ${SESSION} says why"; return 1; }
    # A user unit starts at boot only with linger on; otherwise it waits for you to log in.
    if [[ "$(loginctl show-user "$me" -p Linger --value 2>/dev/null)" == yes ]]; then
        ok "linger is on: it starts at boot, before anyone logs in"
    elif loginctl enable-linger "$me" 2>/dev/null; then
        ok "turned linger on: it starts at boot, before anyone logs in"
    else
        note "it starts when ${me} logs in, not at boot, until linger is on. That takes root:"
        local a=n
        if [[ -t 0 ]]; then read -r -p "     Run 'sudo loginctl enable-linger ${me}' now? [Y/n]: " a || a=n; fi
        case "$a" in
            n|N|no|No) echo "     Later: sudo loginctl enable-linger ${me}" ;;
            *) sudo loginctl enable-linger "$me" && ok "turned linger on" ;;
        esac
    fi
}

install_launchd() {
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by ./existential.sh run host-daemon install; run it again after moving the checkout. -->
<plist version="1.0"><dict>
  <key>Label</key><string>company.existential.host</string>
  <key>WorkingDirectory</key><string>${REPO_DIR}</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(path_line)</string></dict>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>-c</string>
    <string>tmux has-session -t =${SESSION} 2&gt;/dev/null || tmux new -d -s ${SESSION} "exec decree daemon"</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
    ok "wrote ${PLIST/#$HOME/~}"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" && ok "starts when you log in (a Mac starts LaunchAgents at login)"
}

cmd_install() {
    needs || return 1
    echo "The host's decree daemon (${REPO_DIR}/.decree):"
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        install_systemd
    elif [[ "$(uname -s)" == Darwin ]]; then
        install_launchd
    else
        note "no systemd user session or launchd here: it runs now, and you start it at boot yourself"
        echo "     with: cd ${REPO_DIR} && tmux new -d -s ${SESSION} \"exec decree daemon\""
    fi
    start_now
}

cmd_status() {
    local last="" r
    echo "The host's decree daemon (${REPO_DIR}/.decree):"
    if running; then ok "running (tmux attach -t ${SESSION})"; else bad "not running: ./existential.sh run host-daemon install"; fi
    if [[ -f "$UNIT" ]]; then
        if systemctl --user -q is-enabled "${SESSION}.service" 2>/dev/null; then ok "starts at boot (systemd user unit)"; else bad "the unit is there but not enabled: ./existential.sh run host-daemon install"; fi
        [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" == yes ]] \
            && ok "linger on: before anyone logs in" \
            || note "linger off: it starts when you log in, not at boot (sudo loginctl enable-linger $(id -un))"
    elif [[ -f "$PLIST" ]]; then ok "starts at login (LaunchAgent)"
    else bad "nothing starts it at boot: ./existential.sh run host-daemon install"; fi
    for r in $(ls -t "${REPO_DIR}/.decree/runs" 2>/dev/null | head -20); do
        last="$(grep -m1 '^reporting:' "${REPO_DIR}/.decree/runs/${r}/0001-report.log" 2>/dev/null)" && break
    done
    [[ -z "$last" ]] || echo "  Last report: ${last#reporting: }"
    [[ ! -f "${REPO_DIR}/.decree/process.log" ]] || { echo "  Last lines of .decree/process.log:"; tail -3 "${REPO_DIR}/.decree/process.log" | sed 's/^/     /'; }
}

cmd_uninstall() {
    if [[ -f "$UNIT" ]]; then
        systemctl --user disable "${SESSION}.service" >/dev/null 2>&1 || true
        rm -f "$UNIT"; systemctl --user daemon-reload 2>/dev/null || true
        ok "removed the systemd user unit"
    fi
    if [[ -f "$PLIST" ]]; then launchctl unload "$PLIST" 2>/dev/null || true; rm -f "$PLIST"; ok "removed the LaunchAgent"; fi
    running && echo "  The daemon still runs now; to stop it: tmux kill-session -t ${SESSION}" || true
}

case "${1:-status}" in
    install)   cmd_install ;;
    status)    cmd_status ;;
    uninstall) cmd_uninstall ;;
    *) echo "usage: ./existential.sh run host-daemon [install|status|uninstall]" >&2; exit 2 ;;
esac
