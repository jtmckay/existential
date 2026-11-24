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
#   x-exist-endpoints decree-go-rest endpoints, added to .decree/decree-go-rest.yml;
#                     each emits to <name> and nothing else
#   x-exist-title, -tagline, -docs, -services, -e2e, -examples: a flow's, read by
#                     ./existential.sh flow and the gates
# A flow (plugins/flows/<name>.md) has no machine: decree gets it as flow_<name>,
# hyphens as underscores, its cron files and order files installed with it. A
# decree_* name in needs: or extends: is one of decree's official plugins
# (decree_order, decree_ai, decree_lease...), which `decree install <name>` adds.
# One that extends an official plugin holds only what it changes (decree 0.6's
# extends), and a needs: entry may be {<need>: <plugin>}, the plugin that meets it.
#
# One way in. The repo's automation/plugins/ is the one source, and plugin_sync,
# run on the host by ./existential.sh, is the only thing that installs: every
# container that mounts the workspace has .decree/plugins/, machines/ and lib/
# read-only. A plugin made in the workspace (by develop from a note, by an agent,
# by another stack) is an offer, a file in workspace/ai/proposed/. A person reads
# it and accepts it on the host (./existential.sh run plugin accept <name>), which
# puts it in automation/plugins/local/ (never in git), for the automation project
# only. The plugin system itself (PLUGIN_KERNEL) is in every project it is tagged
# for, whatever is on, and no accepted plugin can replace it. Run from the decree
# project root.

HANDLERS=".decree/handlers.yml"
REST=".decree/decree-go-rest.yml"
MANIFEST=".decree/plugins/.existential"   # the plugins the sync wrote, so it removes only its own

# notify: every machine tells you things, and decree check fails an emits: that
# names a machine the project lacks. skill: the decree skill in the workspace (automation only).
PLUGIN_KERNEL=" notify skill "

# plugin_src <dir> <name>: the plugin's file: a machine's, a flow's, or one you
# accepted (local/, never in git; a shipped plugin by the same name wins).
plugin_src() {
    if [[ -f "$1/$2.md" ]]; then echo "$1/$2.md"; elif [[ -f "$1/flows/$2.md" ]]; then echo "$1/flows/$2.md"
    elif [[ -f "$1/local/$2.md" ]]; then echo "$1/local/$2.md"; else return 1; fi
}

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

# The name decree knows it by: a flow's is flow_<name>, snake_case.
plugin_decree_name() {  # <dir> <name>
    local src
    src="$(plugin_src "$1" "$2")" || { echo "$2"; return 0; }
    if [[ "$src" == */flows/* ]]; then echo "flow_${2//-/_}"; else echo "$2"; fi
}


# plugin_tags <file>: the projects that run it, one per line (none: automation).
plugin_tags() { yq --front-matter=extract -r '[.["x-exist-project"] // "automation"] | flatten | .[]' "$1"; }

# plugin_wanted <dir> <project> [name...]: every plugin the project should have,
# each once: what is on, the plugin system and the names given, and all they
# need, less whatever is not tagged for this project. Project `none` is a scratch
# project: the names given and all they need, whatever their tags. An official
# plugin is named as it is (decree_order); a flow by its own name (clean-runs).
plugin_wanted() {
    local dir="$1" project="$2" cfg="${PLUGINS_ON:-$1/../plugins.yml}" f n src seen=" " queue=()
    shift 2
    if [[ "$project" != none ]]; then
        [[ -f "$cfg" ]] && while IFS= read -r n; do [[ -n "$n" ]] && queue+=("$n"); done < <(yq -r '.on // [] | .[]' "$cfg")
        for n in $PLUGIN_KERNEL; do plugin_src "$dir" "$n" >/dev/null && queue+=("$n"); done
    fi
    queue+=("$@")
    while [[ ${#queue[@]} -gt 0 ]]; do
        n="${queue[0]}"; queue=("${queue[@]:1}")
        [[ "$seen" == *" ${n} "* ]] && continue
        seen+="${n} "
        if [[ "$n" == decree_* ]]; then echo "$n"; continue; fi   # decree's own: never one of ours
        src="$(plugin_src "$dir" "$n")" || { echo "plugin: no plugin ${n} in ${dir}" >&2; continue; }
        [[ "$project" == none ]] || plugin_tags "$src" | grep -qxF "$project" || continue
        # One you accepted from the workspace runs in the automation project and nowhere else.
        [[ "$src" != */local/* || "$project" == automation || "$project" == none ]] || continue
        echo "$n"
        while IFS= read -r f; do [[ -n "$f" ]] && queue+=("$f"); done < <(plugin_needs "$src")
    done
}

# plugin_write <dir> <name> <out> [when-machines]: the plugin's file as decree
# installs it: its decree name, and its needs by theirs. note_watch also emits to
# every plugin a note starts (their x-exist-when).
plugin_write() {
    local dir="$1" name="$2" out="$3" when="${4:-}" src dn k d
    src="$(plugin_src "$dir" "$name")"; dn="$(plugin_decree_name "$dir" "$name")"
    dn="$dn" yq --front-matter=process '.name = strenv(dn)' "$src" > "$out"
    for k in $(yq --front-matter=extract -r '.needs // [] | .[] | select(tag == "!!str")' "$src"); do
        d="$(plugin_decree_name "$dir" "$k")"
        [[ "$d" == "$k" ]] || a="$k" b="$d" yq --front-matter=process -i '(.needs[] | select(. == strenv(a))) = strenv(b)' "$out"
    done
    ! cmp -s <(yq --front-matter=extract . "$src") <(yq --front-matter=extract . "$out") || cp "$src" "$out"   # as written, when nothing changed
    [[ "$name" != note_watch || -z "$when" ]] ||
        w="$when" yq --front-matter=process -i '.machine.states.watch.emits = ((.machine.states.watch.emits // []) + (strenv(w) | split(" ")) | unique)' "$out"
}

# plugin_sync <dir> <project> [name...]: the project's .decree/plugins/ is what is
# wanted, each written from the repo's file (a changed one is named, not written,
# while auto_update is false), and `decree install` installs it all, archiving an
# installed copy edited in place. What the sync wrote and is no longer wanted
# goes; a plugin file the sync did not write (an official one you added) stays.
# Then what decree does not install: x-exist-lib, handlers, endpoints.
plugin_sync() {
    local dir="$1" project="$2" wanted n dn src auto rc=0 when="" old check
    shift 2
    plugin_convert_05 "$dir"
    wanted="$(plugin_wanted "$dir" "$project" "$@" | xargs)"
    # Not `// true`: yq's alternative treats false as missing.
    auto="$(yq '.auto_update' "${PLUGINS_ON:-${dir}/../plugins.yml}" 2>/dev/null || echo true)"
    mkdir -p .decree/plugins .decree/machines .decree/lib
    old=" $( { cat "$MANIFEST" 2>/dev/null || true; } | xargs) "
    for n in $wanted; do
        src="$(plugin_src "$dir" "$n")" || continue
        [[ -n "$(yq --front-matter=extract -r '.["x-exist-when"] // ""' "$src")" ]] && when+="${n} "
    done
    plugin_extras_clear
    : > "${MANIFEST}.new"
    for n in $wanted; do
        [[ "$n" == decree_* ]] && continue                        # official: decree adds it as a need
        dn="$(plugin_decree_name "$dir" "$n")"; echo "$dn" >> "${MANIFEST}.new"
        plugin_write "$dir" "$n" ".decree/plugins/.${dn}.md" "${when% }"
        if cmp -s ".decree/plugins/.${dn}.md" ".decree/plugins/${dn}.md"; then rm -f ".decree/plugins/.${dn}.md"
        elif [[ -f ".decree/plugins/${dn}.md" && "$auto" == false ]]; then
            echo "plugin: ${n} has a new version (auto_update is off)"; rm -f ".decree/plugins/.${dn}.md"
        else mv ".decree/plugins/.${dn}.md" ".decree/plugins/${dn}.md"; fi
    done
    for dn in $old; do grep -qxF "$dn" "${MANIFEST}.new" || { rm -f ".decree/plugins/${dn}.md"; echo "plugin: ${dn} removed"; }; done
    mv "${MANIFEST}.new" "$MANIFEST"
    plugin_state_links "$project"
    # Named, so decree adds each official plugin they need, recorded as a need; then bare,
    # which removes a deleted plugin's copy and each need nothing needs any more (decree_order
    # never outlives the repo flow on a host). A plugin's cron files install once, then are yours.
    # shellcheck disable=SC2046  # one plugin name per line, split on purpose (bash 3.2: no mapfile)
    if ! check="$( { decree install --no-color $(cat "$MANIFEST") && decree install --no-color; } 2>&1)"; then rc=1; fi
    grep -v '^installed ' <<<"$check" || true
    plugin_state_links "$project"   # and each official plugin decree just added
    ! ls .decree/cron/*.md >/dev/null 2>&1 ||
        echo "plugin: .decree/cron/ is not read (decree 0.6): a schedule of yours is a plugin with only cron: files, offered and accepted"
    plugin_extras "$dir" "$wanted"
    plugin_order_record
    if ! check="$(decree check --no-color 2>&1)"; then
        echo "plugin: decree check fails after the sync:" >&2; printf '%s\n' "$check" | grep -v '^warning' | head -20 >&2; rc=1
    fi
    return $rc
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

# Before the sync writes plugins/: what each plugin it wrote last time added
# beside decree's files goes (its lib, the handlers and endpoints it declares),
# read from its plugin file, which is still there. A handler or endpoint of
# yours, or seeded from an example, is not a plugin's and stays.
plugin_extras_clear() {
    local f k libs=".decree/lib/.plugins"
    if [[ -f "$libs" ]]; then while IFS= read -r k; do [[ -n "$k" ]] && rm -f ".decree/lib/${k}"; done < "$libs"; fi
    : > "$libs"
    for k in $( { cat "$MANIFEST" 2>/dev/null || true; } ); do
        f=".decree/plugins/${k}.md"; [[ -f "$f" ]] || continue
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
# and decree check it, as an accept would; why not, on stderr. Nothing here changes.
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

# plugin_offered <name>: what a person is told about an offer in
# workspace/ai/proposed/: where to read it, and the one command, on the host, that
# installs it. Nothing in a container can.
plugin_offered() {
    local at="workspace/ai/proposed/$1.md"
    [[ -z "${EXIST_TAILNET_NAME:-}" ]] || at="ai/proposed/$1.md, in https://${EXIST_TAILNET_NAME}"
    printf 'Read it first: its scripts would run with this stack'"'"'s credentials.\n  %s\nThen, on the host:\n  ./existential.sh run plugin accept %s\n' "$at" "$1"
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
          if plugin_src "$dir" "$n" >/dev/null; then plugin_write "$dir" "$n" ".decree/plugins/$(plugin_decree_name "$dir" "$n").md"
          elif [[ ! -f ".decree/plugins/${n}.md" ]]; then decree install --no-color "$n" >/dev/null || return 1; fi
      done
      plugin_state_links none
      decree install --no-color >/dev/null || return 1
      plugin_extras "$dir" "$names" )
}
