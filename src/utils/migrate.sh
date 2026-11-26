#!/usr/bin/env bash
# migrate.sh — what an older install needs once to look like a current one. Sourced by
# existential.sh, never run. A fresh clone has nothing here to do: each step checks for
# the old shape first and returns. Each is dated: once every install has run a checkout
# newer than its date for a while, delete it (and its call and test).
#
#   _migrate          the steps that run before the build (existential.sh's _build)
#   _rename_machines  after the host plugin sync, which removes the old machines

# Every step here: remove after 2027-03-01.

# The host's project was host/.decree, and is the repo's own .decree now. What an
# older install has there moves over once (its list of what is on first, into
# automation/plugins.yml), and the rest of host/ is kept in archive/.
_host_move() {
    local old="${SCRIPT_DIR}/host" new="${SCRIPT_DIR}/.decree" d f
    [[ -d "$old" ]] || return 0
    ( REPO_DIR="$SCRIPT_DIR"; . "${SCRIPT_DIR}/src/utils/flows.sh"; plugins_seed )
    mkdir -p "$new"
    for f in boot.sh exist.json controller.json; do
        if [[ -e "${old}/${f}" && ! -e "${new}/${f}" ]]; then mv "${old}/${f}" "${new}/${f}"; fi
    done
    for d in inbox runs store attention; do
        [[ -d "${old}/.decree/${d}" ]] || continue
        mkdir -p "${new}/${d}"
        for f in "${old}/.decree/${d}"/*; do
            if [[ -e "$f" && ! -e "${new}/${d}/${f##*/}" ]]; then mv "$f" "${new}/${d}/"; fi
        done
    done
    # Its daemon would go on running the old project from archive/: stopped here, and
    # _host_plugins says how to start it in the repo.
    if [[ "$(tmux display-message -p -t '=existential-host:' '#{session_path}' 2>/dev/null)" == */host ]]; then
        tmux kill-session -t '=existential-host' 2>/dev/null || true
        # What reporting started from the old lib and store; its next run starts them again.
        # alloy takes the hangup a closing session sends as "reload", so it is killed by name.
        tmux kill-session -t '=reporting-alloy' 2>/dev/null || true
        pkill -f "alloy run ${old}/" 2>/dev/null || true
        tmux kill-session -t '=notify-relay' 2>/dev/null || true
    fi
    d="${SCRIPT_DIR}/archive/host-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${SCRIPT_DIR}/archive" && mv "$old" "$d"
    echo "  The host's decree project moved from host/.decree to .decree (boot.sh too); what was left of host/ is in ${d#"${SCRIPT_DIR}/"}/."
}

# Keys .env.shared no longer has, dropped from an install that still does. Before
# EXIST_CONTROLLER was the one setting, a host named its Loki in EXIST_REPORTING_URL, and
# one with that and no controller took itself for the controller: its controller is that
# Loki's host. The speech keys moved to their services, which took their values at render.
# EXIST_MODEL_API_KEY was merged into EXIST_FLEET_SECRET.
_RETIRED_KEYS='EXIST_(MODEL_API_KEY|REPORTING_URL|HOST_ADDRESS|MODEL_SERVICE|COMFYUI_URL|MODEL_URL_CHAT|MODEL_URL_VISION|MODEL_STT|MODEL_STT_LANGUAGE|MODEL_TTS_VOICE)'
# Flows that were renamed, in automation/plugins.yml's on: list, so a host that had one on
# keeps it on, under the name its machine has: <old> <new>.
_RENAMED_FLOWS='auto-update pull-existential
worker report-host
on-boot boot-daemon
ai-box lease-gpu'
_rename_flows() {
    local f="${SCRIPT_DIR}/automation/plugins.yml" old new t
    [[ -f "$f" ]] || return 0
    while read -r old new; do
        grep -qE "(^[[:space:]]*-[[:space:]]*|[[, ])${old}([[:space:]]*$|[], ])" "$f" || continue
        t="$(mktemp)"
        sed -e "s/^\([[:space:]]*-[[:space:]]*\)${old}[[:space:]]*\$/\1${new}/" \
            -e "s/\([[, ]\)${old}\([], ]\)/\1${new}\2/g" "$f" > "$t" && cat "$t" > "$f"
        rm -f "$t"
        echo "  The ${old} flow is ${new} now; it stays on."
    done <<<"$_RENAMED_FLOWS"
}

# Machines that were renamed: <old> <new>. decree removes a machine whose plugin is gone but
# keeps its state/ (and leaves its graph.md): what it kept moves to the new machine, as long as
# the new one has none of its own yet (report_host's alloy positions, so no run log ships
# twice), and the old folder goes once nothing but its graph is left.
_RENAMED_MACHINES='reporting report_host
update pull_existential
auto_update pull_existential
boot boot_daemon
on_boot boot_daemon
ubuntu_upgrade update_ubuntu
ai_box_gpu lease_gpu'
_rename_machines() {
    local m="${SCRIPT_DIR}/.decree/machines" old new f
    while read -r old new; do
        [[ -d "${m}/${old}" && ! -f "${m}/${old}/machine.yml" && -f "${m}/${new}/machine.yml" ]] || continue
        # reporting's alloy writes into its state: stopped first, and report_host's next run
        # starts it on the new folder. alloy takes a closing session's hangup as "reload".
        if [[ "$old" == reporting ]]; then
            tmux kill-session -t '=reporting-alloy' 2>/dev/null || true
            pkill -f 'alloy run .decree/lib/reporting/decree.alloy' 2>/dev/null || true
        fi
        if [[ -d "${m}/${old}/state" ]]; then
            mkdir -p "${m}/${new}/state"
            for f in "${m}/${old}/state"/* "${m}/${old}/state"/.[!.]*; do
                [[ -e "$f" ]] || continue
                # The new machine's own copy wins; the old one is stale.
                if [[ -e "${m}/${new}/state/${f##*/}" ]]; then rm -rf "$f"; else mv "$f" "${m}/${new}/state/"; fi
            done
            rmdir "${m}/${old}/state" 2>/dev/null || continue
        fi
        rm -f "${m}/${old}/graph.md"
        rmdir "${m}/${old}" 2>/dev/null && echo "  ${old} is ${new} now; what it kept moved with it."
    done <<<"$_RENAMED_MACHINES"
}

_retire_env_keys() {
    local f="${SCRIPT_DIR}/.env.shared" url ctl t key
    grep -qE "^${_RETIRED_KEYS}=" "$f" 2>/dev/null || return 0
    url=$(grep -m1 '^EXIST_REPORTING_URL=' "$f" | cut -d= -f2-) || true
    ctl=$(grep -m1 '^EXIST_CONTROLLER=' "$f" | cut -d= -f2-) || true
    t="$(mktemp)"
    grep -vE "^${_RETIRED_KEYS}=" "$f" > "$t" || true
    # EXIST_MODEL_API_KEY is EXIST_FLEET_SECRET now: a host with no secret takes its value.
    key=$(grep -m1 '^EXIST_MODEL_API_KEY=' "$f" | cut -d= -f2-) || true
    if [[ -n "$key" ]] && ! grep -qE '^EXIST_FLEET_SECRET=.+' "$t"; then
        grep -v '^EXIST_FLEET_SECRET=' "$t" > "${t}.2" || true
        echo "EXIST_FLEET_SECRET=${key}" >> "${t}.2"; mv "${t}.2" "$t"
    fi
    if [[ -n "$url" && -z "$ctl" ]] && ! grep -q '^EXIST_IS_HOSTING_LOKI=true' "$f"; then
        ctl="${url#*://}"; ctl="${ctl%%[:/]*}"
        awk -v c="$ctl" '/^EXIST_CONTROLLER=/ && !d { print "EXIST_CONTROLLER=" c; d = 1; next } { print }' "$t" > "${t}.2"
        grep -q '^EXIST_CONTROLLER=' "${t}.2" || echo "EXIST_CONTROLLER=${ctl}" >> "${t}.2"
        mv "${t}.2" "$t"
        echo "  EXIST_REPORTING_URL is gone: this host now names its controller, EXIST_CONTROLLER=${ctl}."
    fi
    cat "$t" > "$f"; rm -f "$t"
}

# A compose file rendered before, without asking: decree 0.6's code is plugins/,
# where 0.5's was scripts/, and the workspace's .decree is no longer mounted
# read-only over it (automation-backup's own project still is).
_decree_code_mounts() {
    local d f
    while IFS= read -r d; do
        f="${d}/docker-compose.yml"
        [[ -f "$f" ]] || continue
        if grep -q '/\.decree/scripts:' "$f"; then
            sed -i.bak 's#\([./a-z_]*\)/scripts:\([^:]*\)/\.decree/scripts:#\1/plugins:\2/.decree/plugins:#' "$f" && rm -f "${f}.bak"
            echo "  ${f#"${SCRIPT_DIR}/"}: .decree/plugins/ is mounted read-only (decree 0.6)"
        fi
        # The workspace's own decree code was mounted read-only over it; now it is yours to write.
        if grep -qE '^[[:space:]]*- workspace_data/\.decree/(machines|plugins|lib):' "$f"; then
            sed -i.bak -E '/^[[:space:]]*- workspace_data\/\.decree\/(machines|plugins|lib):/d' "$f" && rm -f "${f}.bak"
            echo "  ${f#"${SCRIPT_DIR}/"}: workspace/.decree is writable (your own plugins go in its plugins/)"
        fi
    done < <(_find_service_dirs)
}

_migrate() {
    _host_move
    _decree_code_mounts
    _retire_env_keys
    _rename_flows
}
