#!/usr/bin/env bash
# plugin.sh — which of the repo's plugins a decree project has, written
# into its .decree/plugins/ for `decree install`, which installs them.
#
# A plugin is a decree plugin file (name, machine, scripts, cron, state, order,
# needs: decree installs each into .decree/machines/<name>/, and an edit made in
# place goes to .decree/archive/ on the next install), with existential's keys
# beside decree's, which decree ignores:
#   x-exist-project   which decree project runs it: automation, backup or host, or
#                     a list. A project installs only what is tagged for it, so
#                     nothing the automation daemon can reach lands in the others
#   x-exist-lib       <path>: <its text>, each to .decree/lib/<path>, which every
#                     script reaches as .decree/lib/<path> (a script runs in the
#                     project root). The repo's automation/lib/ goes there too
#   x-exist-handlers  file-change triggers, [{match, changes, quiet}], each added to
#                     .decree/handlers.yml for this machine
#   x-exist-when      the kind of note that starts it: note_watch asks the model
#                     whether a note is that, and emits to this machine
#   x-exist-topic     the ntfy topic a failed or waiting run of it is told on (host for
#                     the server's own work; default decree), by lib/attention-notify.sh
#   x-exist-endpoints decree-go-rest endpoints, added to .decree/decree-go-rest.yml;
#                     each emits to <name> and nothing else
# A plugin with no machine is lib others need (model, pi, fleet...). A decree_* name
# in needs: or extends: is one of decree's official plugins (decree_order,
# decree_ai, decree_lease...), which `decree install <name>` adds. One that extends
# an official plugin holds only what it changes (decree 0.6's extends), and a
# needs: entry may be {<need>: <plugin>}, the plugin that meets it.
#
# The repo's automation/plugins/ is every plugin there is, and none of it is on.
# What a project has on is its own .decree/plugins/.on, one name per line: what
# `./existential.sh plugin on` put there (a new project starts with
# PLUGIN_DEFAULTS). plugin_sync, run on the host by ./existential.sh, writes each
# of those and all they need into .decree/plugins/ at the checkout's version, and
# removes a repo plugin nothing on needs any more. In the workspace project
# (automation) a plugin file of your own goes in .decree/plugins/ and `decree
# install <name>` installs it; the sync leaves a file whose name is not the repo's
# alone. The plugin system itself (PLUGIN_KERNEL) is in every project it is tagged
# for, whatever is on. Run from the decree project root.

HANDLERS=".decree/handlers.yml"
REST=".decree/decree-go-rest.yml"
ON=".decree/plugins/.on"                  # what is on in this project, one name per line
YOURS=".decree/plugins/.yours"            # your own plugin files it saw, so a deleted one's handlers go

# notify: every machine tells you things, and decree check fails an emits: that
# names a machine the project lacks. skill: the decree skill in the workspace
# (automation only). decree_prune: finished runs pruned after 30 days.
PLUGIN_KERNEL=" notify skill decree_prune "
# What a new project starts with: what every install does without being asked.
PLUGIN_DEFAULTS=" note_watch reconcile service_health pi file_advise you_were_here "

# plugin_src <dir> <name>: the plugin's file.
plugin_src() { [[ -f "$1/$2.md" ]] && echo "$1/$2.md"; }

plugin_is() {  # <file>: true when it is a plugin, not a spec: it carries a machine or cron files, or extends one
    [[ "$(yq --front-matter=extract '[.machine, .cron] | map(tag) | join(" ")' "$1" 2>/dev/null)" == *'!!map'* ||
       -n "$(yq --front-matter=extract -r '.extends // ""' "$1" 2>/dev/null)" ]]
}

# plugin_needs <file>: every plugin it relies on, one per line: what it extends,
# and each need, a {need: plugin} entry's both.
plugin_needs() {
    yq --front-matter=extract -r '[.extends // [], (.needs // [] | .[] | select(tag == "!!str")),
        (.needs // [] | .[] | select(tag == "!!map") | to_entries | .[] | [.key, .value])] | flatten | .[]' "$1"
}

# plugin_tags <file>: the projects that run it, one per line (none: automation).
plugin_tags() { yq --front-matter=extract -r '[.["x-exist-project"] // "automation"] | flatten | .[]' "$1"; }

# plugin_wanted <dir> <project> [name...]: every plugin the project should have,
# each once: what is on, the plugin system and the names given, and all they
# need, less whatever is not tagged for this project. Project `none` is a scratch
# project: the names given and all they need, whatever their tags. An official
# plugin is named as it is (decree_order).
plugin_wanted() {
    local dir="$1" project="$2" f n src seen=" " queue=()
    shift 2
    if [[ "$project" != none ]]; then
        [[ -f "$ON" ]] && while IFS= read -r n; do [[ -n "$n" ]] && queue+=("$n"); done < "$ON"
        for n in $PLUGIN_KERNEL; do
            { [[ "$n" == decree_* ]] || plugin_src "$dir" "$n" >/dev/null; } && queue+=("$n")
        done
    fi
    queue+=("$@")
    while [[ ${#queue[@]} -gt 0 ]]; do
        n="${queue[0]}"; queue=("${queue[@]:1}")
        [[ "$seen" == *" ${n} "* ]] && continue
        seen+="${n} "
        if [[ "$n" == decree_* ]]; then echo "$n"; continue; fi   # decree's own: never one of ours
        src="$(plugin_src "$dir" "$n")" || { echo "plugin: no plugin ${n} in ${dir}" >&2; continue; }
        [[ "$project" == none ]] || plugin_tags "$src" | grep -qxF "$project" || continue
        echo "$n"
        while IFS= read -r f; do [[ -n "$f" ]] && queue+=("$f"); done < <(plugin_needs "$src")
    done
}

# plugin_write <dir> <name> <out> [when-machines]: the plugin's file as decree
# installs it. note_watch also emits to every plugin a note starts (their x-exist-when).
plugin_write() {
    local src="$1/$2.md" out="$3" when="${4:-}"
    cp "$src" "$out"
    [[ "$2" != note_watch || -z "$when" ]] ||
        w="$when" yq --front-matter=process -i '.machine.states.watch.emits = ((.machine.states.watch.emits // []) + (strenv(w) | split(" ")) | unique)' "$out"
}

# plugin_sync <dir> <project> [name...]: the project's .decree/plugins/ is what is
# wanted, each written from the repo's file, and `decree install` installs it all,
# archiving an installed copy edited in place. A repo plugin no longer wanted goes;
# a plugin file whose name is not the repo's (yours, or an official one you added)
# stays. Then what decree does not install: x-exist-lib, handlers, endpoints.
plugin_sync() {
    local dir="$1" project="$2" wanted n src rc=0 when="" check f mine="" theirs="" names=""
    shift 2
    plugin_convert_05 "$dir"
    plugin_seed "$dir" "$project" || return 1
    mkdir -p .decree/machines .decree/lib
    # Your own plugin files in the workspace project, installed by `decree install`:
    # never written or removed here, only given what decree does not install, and
    # the repo's plugins they need.
    if [[ "$project" == automation ]]; then
        for f in .decree/plugins/*.md; do
            [[ -f "$f" ]] || continue; n="$(basename "$f" .md)"
            [[ "$n" == decree_* ]] && continue
            plugin_src "$dir" "$n" >/dev/null && continue
            mine+="${n} "
            [[ -n "$(yq --front-matter=extract -r '.["x-exist-when"] // ""' "$f")" ]] && when+="${n} "
            for n in $(plugin_needs "$f"); do plugin_src "$dir" "$n" >/dev/null && theirs+="${n} "; done
        done
    fi
    # shellcheck disable=SC2086  # names, split on purpose
    wanted="$(plugin_wanted "$dir" "$project" "$@" $theirs | xargs)"
    for n in $wanted; do
        src="$(plugin_src "$dir" "$n")" || continue
        [[ -n "$(yq --front-matter=extract -r '.["x-exist-when"] // ""' "$src")" ]] && when+="${n} "
    done
    plugin_extras_clear "$dir" "$mine"
    for n in $wanted; do
        if [[ "$n" == decree_* ]]; then   # official: decree adds it as a need, or named, the kernel's
            [[ "$PLUGIN_KERNEL" != *" ${n} "* ]] || names+="${n} "
            continue
        fi
        names+="${n} "
        plugin_write "$dir" "$n" ".decree/plugins/.${n}.md" "${when% }"
        if cmp -s ".decree/plugins/.${n}.md" ".decree/plugins/${n}.md"; then rm -f ".decree/plugins/.${n}.md"
        else mv ".decree/plugins/.${n}.md" ".decree/plugins/${n}.md"; fi
    done
    for f in .decree/plugins/*.md; do
        [[ -f "$f" ]] || continue; n="$(basename "$f" .md)"
        [[ " ${wanted} " == *" ${n} "* ]] && continue
        plugin_src "$dir" "$n" >/dev/null || continue
        rm -f "$f"; echo "plugin: ${n} removed"
    done
    plugin_state_links "$project"
    # Named, so decree adds each official plugin they need, recorded as a need; then bare,
    # which removes a deleted plugin's copy and each need nothing needs any more (decree_order
    # never outlives the repo plugin on a host). A plugin's cron files install once, then are yours.
    # shellcheck disable=SC2086  # one plugin name each, split on purpose (bash 3.2: no mapfile)
    if ! check="$( { decree install --no-color $names && decree install --no-color; } 2>&1)"; then rc=1; fi
    grep -v '^installed ' <<<"$check" || true
    plugin_state_links "$project"   # and each official plugin decree just added
    ! ls .decree/cron/*.md >/dev/null 2>&1 ||
        echo "plugin: .decree/cron/ is not read (decree 0.6): a schedule of yours is a plugin with only cron: files, offered and accepted"
    plugin_extras "$dir" "$wanted"
    [[ -z "$mine" ]] || plugin_extras .decree/plugins "$mine"
    # One of yours whose file you deleted: its handlers go too.
    for n in $(cat "$YOURS" 2>/dev/null || true); do
        [[ " $mine " == *" ${n} "* || ! -f "$HANDLERS" ]] || n="$n" yq -i 'del(.[] | select(.machine == strenv(n)))' "$HANDLERS"
    done
    if [[ "$project" == automation ]]; then printf '%s\n' $mine > "$YOURS"; fi
    plugin_order_record
    if ! check="$(decree check --no-color 2>&1)"; then
        echo "plugin: decree check fails after the sync:" >&2; printf '%s\n' "$check" | grep -v '^warning' | head -20 >&2; rc=1
    fi
    return $rc
}

# plugin_seed <dir> <project>: a project with no list of what is on starts with the
# defaults tagged for it. One an older checkout synced has its list in its old form
# until ./existential.sh's migration turns it into this one.
plugin_seed() {
    local n src
    mkdir -p .decree/plugins
    [[ ! -f "$ON" ]] || return 0
    if [[ -f .decree/plugins/.existential ]]; then
        echo "plugin: run ./existential.sh once first: it turns this project's old list of what is on into ${ON}" >&2; return 1
    fi
    for n in $PLUGIN_DEFAULTS; do
        src="$(plugin_src "$1" "$n")" && plugin_tags "$src" | grep -qxF "$2" && echo "$n"
    done > "$ON"
    return 0
}

# plugin_turn on|off <dir> <project> <name>: in this project's list of what is on, or out of it.
plugin_turn() {
    plugin_seed "$1" "$2" || return 1
    grep -vxF "$4" "$ON" > "${ON}.new" || true
    [[ "$1" == off ]] || echo "$4" >> "${ON}.new"
    mv "${ON}.new" "$ON"
}

# Each machine's state/: in a project a container mounts with machines/ read-only
# (automation, backup), a link to .decree/store/<name>/, which stays writable and
# is where a person edits a plugin's data (feeds, taste, departments). The host's
# project has no such mount, so its state/ is a folder, as decree makes it.
plugin_state_links() {  # <project>
    local f n
    mkdir -p .decree/store
    if [[ "$1" == host ]]; then   # decree 0.5 kept a machine's state in store/<name>/: it moves, once
        for f in .decree/plugins/*.md; do
            n="$(basename "$f" .md)"
            [[ -d ".decree/store/${n}" && ! -e ".decree/machines/${n}/state" ]] || continue
            mkdir -p ".decree/machines/${n}"; mv ".decree/store/${n}" ".decree/machines/${n}/state"
        done
        return 0
    fi
    for f in .decree/plugins/*.md; do
        [[ -f "$f" ]] || continue
        n="$(basename "$f" .md)"
        mkdir -p ".decree/machines/${n}" ".decree/store/${n}"
        if [[ -d ".decree/machines/${n}/state" && ! -L ".decree/machines/${n}/state" ]]; then
            cp -rn ".decree/machines/${n}/state/." ".decree/store/${n}/"; rm -rf ".decree/machines/${n}/state"
        fi
        [[ -L ".decree/machines/${n}/state" ]] || ln -s "../../store/${n}" ".decree/machines/${n}/state"
    done
}

# Before the sync writes plugins/: what each repo plugin installed here added
# beside decree's files goes (its lib, the handlers and endpoints it declares),
# read from its plugin file, which is still there; and the same for each of your
# own plugin files named. A handler or endpoint of yours, or seeded from an
# example, is not a plugin's and stays.
plugin_extras_clear() {  # <dir> [your plugins]
    local f k libs=".decree/lib/.plugins"
    if [[ -f "$libs" ]]; then while IFS= read -r k; do [[ -n "$k" ]] && rm -f ".decree/lib/${k}"; done < "$libs"; fi
    : > "$libs"
    for f in .decree/plugins/*.md; do
        [[ -f "$f" ]] || continue; k="$(basename "$f" .md)"
        plugin_src "$1" "$k" >/dev/null || [[ " ${2:-} " == *" ${k} "* ]] || continue
        if [[ -f "$HANDLERS" ]]; then
            yq --front-matter=extract '[.["x-exist-handlers"][]? | .match]' "$f" > "${TMPDIR:-/tmp}/exist-match.yml"
            n="$k" yq -i "del(.[] | select(.machine == strenv(n) and ([.match] - load(\"${TMPDIR:-/tmp}/exist-match.yml\") | length) == 0))" "$HANDLERS"
        fi
        if [[ -f "$REST" ]]; then
            yq --front-matter=extract '[.["x-exist-endpoints"][]? | .path]' "$f" > "${TMPDIR:-/tmp}/exist-paths.yml"
            yq -i "del(.endpoints[] | select(([.path] - load(\"${TMPDIR:-/tmp}/exist-paths.yml\") | length) == 0))" "$REST"
        fi
    done
}

# What decree does not install: each wanted plugin's x-exist-lib in .decree/lib/,
# its handlers and its endpoints.
plugin_extras() {  # <dir> <wanted>
    local dir="$1" n src k libs=".decree/lib/.plugins"
    for n in $2; do
        src="$(plugin_src "$dir" "$n")" || continue
        for k in $(yq --front-matter=extract -r '.["x-exist-lib"] // {} | keys | .[]' "$src"); do
            mkdir -p "$(dirname ".decree/lib/${k}")"
            printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.["x-exist-lib"][strenv(k)]' "$src")" > ".decree/lib/${k}"
            if [[ "$(head -c2 ".decree/lib/${k}")" == '#!' ]]; then chmod 755 ".decree/lib/${k}"; else chmod 644 ".decree/lib/${k}"; fi
            echo "$k" >> "$libs"
        done
        if [[ "$(yq --front-matter=extract '.["x-exist-handlers"] // [] | length' "$src")" != 0 ]]; then
            touch "$HANDLERS"
            yq --front-matter=extract '.["x-exist-handlers"]' "$src" > "${TMPDIR:-/tmp}/exist-handlers.yml"
            n="$n" yq -i ". = ((. // []) + (load(\"${TMPDIR:-/tmp}/exist-handlers.yml\")
                | map({\"match\": .match, \"machine\": strenv(n), \"changes\": (.changes // [\"created\"]), \"quiet\": (.quiet // 30)})))" "$HANDLERS"
        fi
        if [[ "$(yq --front-matter=extract '.["x-exist-endpoints"] // [] | length' "$src")" != 0 ]]; then
            if [[ -f "$REST" ]]; then
                yq --front-matter=extract '.["x-exist-endpoints"]' "$src" > "${TMPDIR:-/tmp}/exist-endpoints.yml"
                yq -i ".endpoints += load(\"${TMPDIR:-/tmp}/exist-endpoints.yml\")" "$REST"
            else echo "plugin: ${n} has endpoints, and there is no ${REST} (turn on automation-webhook)"; fi
        fi
    done
}

# A migration that ran (decree 0.5's processed.md) is an order file that ran: it
# is recorded in its machine's state/order.git.txt, so `order` does not run it
# again. Then any order file that has not run waits for the next daemon start, so
# one run of `order` is queued for it now.
plugin_order_record() {
    local f m name rec pending=false
    for f in .decree/machines/*/order/*.md; do
        [[ -f "$f" ]] || continue
        m="${f#.decree/machines/}"; m="${m%%/*}"; name="$(basename "$f")"; rec=".decree/machines/${m}/state/order.git.txt"
        grep -q "^${name} " "$rec" 2>/dev/null && continue
        if grep -qxF "$name" .decree/processed.md 2>/dev/null; then
            mkdir -p "$(dirname "$rec")"
            echo "${name} $( { sha256sum "$f" 2>/dev/null || shasum -a 256 "$f"; } | cut -d' ' -f1)" >> "$rec"
        else pending=true; fi
    done
    [[ ! -f .decree/processed.md ]] || { mkdir -p .decree/archive/0.5; mv .decree/processed.md .decree/archive/0.5/; }
    $pending && [[ -f .decree/machines/decree_order/machine.yml ]] && ! grep -qlx 'machine: decree_order' .decree/inbox/*.md 2>/dev/null &&
        echo "Run the order files that have not run." |
        decree emit --machine decree_order >/dev/null && echo "plugin: order files are queued to run"
    return 0
}

# decree 0.5's layout, once: what a plugin installed goes (the plugin installs it
# again where decree 0.6 keeps it), a machine of yours moves to machines/<name>/,
# and the rest (registry, applied copies, migrations, flat scripts) is kept in
# .decree/archive/0.5/. processed.md stays until plugin_order_record has read it.
plugin_convert_05() {  # <dir>
    local f n keep=.decree/archive/0.5 reg=.decree/automations.yml
    compgen -G '.decree/machines/*.yml' >/dev/null || [[ -f "$reg" || -d .decree/migrations || -d .decree/applied ]] || return 0
    mkdir -p "$keep"
    for f in .decree/machines/*.yml; do
        [[ -f "$f" ]] || continue
        n="$(basename "$f" .yml)"
        if plugin_src "$1" "$n" >/dev/null || { [[ -f "$reg" ]] && n="$n" yq -e '.[] | select(.machine == strenv(n) and .kind == "plugin")' "$reg" >/dev/null 2>&1; }; then
            rm -f "$f"; rm -rf ".decree/scripts/${n}"
        else
            mkdir -p ".decree/machines/${n}"; mv "$f" ".decree/machines/${n}/machine.yml"
            [[ ! -d ".decree/scripts/${n}" ]] || mv ".decree/scripts/${n}" ".decree/machines/${n}/scripts"
            echo "plugin: your machine ${n} is now .decree/machines/${n}/ (decree 0.6)"
        fi
    done
    # Lib files a plugin wrote: written again from x-exist-lib.
    [[ ! -f "$reg" ]] || for f in $(yq -r '.[] | .libs[]?' "$reg"); do rm -f ".decree/lib/${f}"; done
    # Their handlers and endpoints go too: the sync adds back those of the plugins still on.
    if [[ -f "$reg" ]]; then
        n="$(yq -r '[.[] | select(.kind == "plugin") | .machine] | join(",")' "$reg")"
        [[ ! -f "$HANDLERS" ]] || m="$n" yq -i 'del(.[] | select(.machine as $x | strenv(m) | split(",") | any_c(. == $x)))' "$HANDLERS"
        [[ ! -f "$REST" ]] || m="$n" yq -i 'del(.endpoints[] | select(.message.machine as $x | strenv(m) | split(",") | any_c(. == $x)))' "$REST"
    fi
    # The plugins' cron files are installed again in their machine's folder (an
    # edit of one is kept in the archive, to make again); yours stay in .decree/cron/,
    # which decree 0.6 does not read, and the sync says so.
    mkdir -p "$keep/cron"
    [[ ! -f "$reg" ]] || for f in $(yq -r '.[] | .crons[]?' "$reg"); do [[ ! -f ".decree/cron/${f}.md" ]] || mv ".decree/cron/${f}.md" "$keep/cron/"; done
    for f in "$reg" .decree/applied .decree/migrations .decree/scripts .decree/graph; do [[ ! -e "$f" ]] || mv "$f" "$keep/"; done
    echo "plugin: decree 0.5's installed copies are replaced; what is left of them is in ${keep}/"
}


# plugin_try <file>: install one plugin file into a scratch copy of this project
# and decree check it; why not, on stderr. Nothing here changes.
plugin_try() {
    local work out
    work="$(mktemp -d)"; mkdir -p "${work}/.decree"
    cp -r .decree/plugins "${work}/.decree/"
    [[ ! -f "$REST" ]] || cp "$REST" "${work}/${REST}"
    if ! out="$(cd "$work" && decree install --no-color >/dev/null && decree install --no-color "$1" 2>&1 && decree check --no-color 2>&1)"; then
        grep -v '^warning' <<<"$out" | head -5 >&2; rm -rf "$work"; return 1
    fi
    rm -rf "$work"
}

# plugin_offered <name>: what a person is told about a plugin file in
# workspace/ai/proposed/: read it, then install it from the workspace.
plugin_offered() {
    printf 'Read it first: its scripts would run with this stack'"'"'s credentials. To install it:\n  mv ai/proposed/%s.md .decree/plugins/ && decree install %s\n' "$1" "$1"
}

# plugin_unpack <name>... <project root>: the repo's plugins, and all they need,
# installed there with the plugin system's lib: a test's or the gate's scratch
# project. A plugin's scripts are then <root>/.decree/machines/<name>/scripts/.
plugin_unpack() {
    local root="${!#}" lib dir n names
    lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; dir="$(cd "${lib}/../plugins" && pwd)"
    mkdir -p "${root}/.decree/lib" "${root}/.decree/plugins"
    cp -rp "${lib}/." "${root}/.decree/lib/"
    ( cd "$root" && { [[ -f "$REST" ]] || echo 'endpoints: []' > "$REST"; }
      names="$(plugin_wanted "$dir" none "${@:1:$#-1}" | xargs)"
      for n in $names; do
          if plugin_src "$dir" "$n" >/dev/null; then plugin_write "$dir" "$n" ".decree/plugins/${n}.md"
          elif [[ ! -f ".decree/plugins/${n}.md" ]]; then decree install --no-color "$n" >/dev/null || return 1; fi
      done
      plugin_state_links none
      decree install --no-color >/dev/null || return 1
      plugin_extras "$dir" "$names" )
}
