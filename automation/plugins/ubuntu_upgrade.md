---
machine: plugin
automation: ubuntu_upgrade
chart:
  description: Once a week, install every Ubuntu package update that is not a release upgrade, and reboot at the configured time only if one of them requires it. Ubuntu's own unattended-upgrades does the daily security updates.
  initial: upgrade
  states:
    upgrade:
      # apt killed halfway leaves dpkg to repair by hand, so the timeout is long.
      invoke:
        script: {name: upgrade, timeout: 3h}
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  upgrade: |
    #!/usr/bin/env bash
    # upgrade — the weekly maintenance window: run the root half, which setup.sh
    # installed, and tell your phone when it failed or a reboot is coming. Nothing
    # here is root: the one thing sudo allows is that installed script. Runs in the
    # host project (host/.decree), so the repo is one up.
    set -euo pipefail
    repo="$(cd .. && pwd)"
    lib="${DECREE_LIB:-${PWD}/.decree/lib}/ubuntu_upgrade"
    root=/usr/local/sbin/existential-ubuntu-upgrade
    # shellcheck source=/dev/null
    . "${repo}/src/utils/adhoc.sh"
    adhoc_find_runtime || true
    tell() {  # <title> <body>: to your phone, through the stack's own notify, when there is one here
        printf '%s\n' "$2" | ${DOCKER_CMD:-false} exec -i automation decree emit --machine notify \
            --param ntfy_title="$1" --param ntfy_tags=package >/dev/null 2>&1 || true
    }
    grep -qs '^ID=ubuntu$' /etc/os-release || { echo "ubuntu_upgrade: this host is not Ubuntu; turn the flow off here" >&2; exit 1; }
    # Not set up, or the repo's upgrade.sh changed since: a person runs setup again.
    if ! cmp -s "${lib}/upgrade.sh" "$root" || ! sudo -n -l "$root" >/dev/null 2>&1; then
        echo "ubuntu_upgrade: set it up once, as root, then retry:  sudo bash ${lib}/setup.sh" >&2
        tell "Ubuntu upgrade needs setup" "$(hostname): sudo bash ${lib}/setup.sh"
        exit 1
    fi
    if ! out="$(sudo -n "$root" 2>&1)"; then
        printf '%s\n' "$out" >&2
        tell "Ubuntu upgrade failed" "$(hostname): $(printf '%s\n' "$out" | tail -5)"
        exit 1
    fi
    printf '%s\n' "$out"
    reboot="$(printf '%s\n' "$out" | grep '^reboot: ' || true)"
    [[ -z "$reboot" ]] || tell "Ubuntu upgraded" "$(hostname) ${reboot}"
lib:
  ubuntu_upgrade/upgrade.sh: |
    #!/usr/bin/env bash
    # The root half of ubuntu_upgrade, installed by setup.sh as
    # /usr/local/sbin/existential-ubuntu-upgrade, the one command sudo lets the
    # host daemon run. `upgrade`, never `dist-upgrade` or do-release-upgrade: no
    # package is removed and the release never changes. A changed config file
    # keeps your version. Whether and when to reboot is unattended-upgrades' own
    # setting (/etc/apt/apt.conf.d/52existential-updates), read here so the two agree.
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get -q -o DPkg::Lock::Timeout=600 update
    apt-get -q -y -o DPkg::Lock::Timeout=600 --with-new-pkgs \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
    [ -f /var/run/reboot-required ] || exit 0
    reboot=false; at=02:00
    eval "$(apt-config shell reboot Unattended-Upgrade::Automatic-Reboot at Unattended-Upgrade::Automatic-Reboot-Time)"
    if [ "$reboot" = true ]; then
        shutdown -r "$at" "existential: an Ubuntu update requires a reboot" 2>/dev/null
        echo "reboot: required, and happens at ${at}"
    else
        echo "reboot: required, and automatic reboots are off, so it waits for you"
    fi
  ubuntu_upgrade/setup.sh: |
    #!/usr/bin/env bash
    # setup.sh — the one root step of the update-ubuntu flow. Safe to run again;
    # run it again when ubuntu_upgrade says upgrade.sh changed.
    #
    #   sudo bash host/.decree/lib/ubuntu_upgrade/setup.sh
    #
    # 1. unattended-upgrades on: package lists and security updates daily, and a
    #    reboot at 02:00 only when an installed update requires one. The file is
    #    written once and is yours after.
    # 2. upgrade.sh installed root-owned, and sudo allowed to run exactly that,
    #    without a password, for the account that ran this.
    set -euo pipefail
    [ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0" >&2; exit 1; }
    user="${SUDO_USER:?run with sudo, from the account the host daemon runs as}"
    here="$(cd "$(dirname "$0")" && pwd)"
    grep -qs '^ID=ubuntu$' /etc/os-release || { echo "this host is not Ubuntu" >&2; exit 1; }

    dpkg -s unattended-upgrades >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -y install unattended-upgrades
    conf=/etc/apt/apt.conf.d/52existential-updates
    [ -f "$conf" ] || cat > "$conf" <<'EOF'
    // existential's update-ubuntu flow wrote this once; it is yours to edit.
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Unattended-Upgrade "1";
    // "false": nothing reboots this host, and your phone says when one is due.
    Unattended-Upgrade::Automatic-Reboot "true";
    Unattended-Upgrade::Automatic-Reboot-Time "02:00";
    EOF
    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

    install -o root -g root -m 755 "${here}/upgrade.sh" /usr/local/sbin/existential-ubuntu-upgrade
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    printf '%s ALL=(root) NOPASSWD: /usr/local/sbin/existential-ubuntu-upgrade\n' "$user" > "$tmp"
    visudo -cf "$tmp" >/dev/null
    install -o root -g root -m 440 "$tmp" /etc/sudoers.d/existential-ubuntu-upgrade
    echo "set up: security updates daily, everything else Sundays at 01:00, reboots per ${conf}"
cron:
  ubuntu-upgrade: |
    ---
    machine: ubuntu_upgrade
    cron: "0 1 * * SUN"
    ---

    The weekly maintenance window: Sundays at 01:00, an hour before the reboot time.
---
# ubuntu_upgrade

The weekly half of keeping an Ubuntu host patched: Sundays at 01:00 it installs every package
update (`apt-get upgrade`, so nothing is removed and the release never changes), and schedules
a reboot for 02:00 only when one of them requires it. Your phone hears a failure, and a reboot
that is coming. The daily half, security updates, is Ubuntu's own `unattended-upgrades`, which
`setup.sh` turns on.

It runs in the host's own decree project, `host/.decree`, without root: `setup.sh`, run once
with sudo, installs the one script sudo then lets it run. The `update-ubuntu` flow turns it on:
`./existential.sh flow on update-ubuntu`.
