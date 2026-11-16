#!/usr/bin/env bash
# automations/plugin.sh — install, update and remove plugins, and export an
# installed machine as one.
#
# A plugin is one file whose frontmatter carries the whole machine, so it is
# installed as written and no model is asked:
#   chart:      the machine, without `name` (it is <name>). A plugin with none
#               is a flow, in plugins/flows/: what one curated thing needs (its
#               needs:, services:, cron and migrations), or lib others need (model)
#   scripts:    <script>: <its text>, each to .decree/scripts/<name>/<script>.sh
#   lib:        <path>: <its text>, each to .decree/lib/<path>, where any script
#               reaches it as ${DECREE_LIB}/<path>; executable when it starts #!.
#               The repo's automation/lib/ is only the plugin system's; all
#               other code is in a plugin
#   store:      <path>: <its text>, each to .decree/store/<name>/<path> once: data
#               that is yours to edit (feeds, taste, departments), which is never
#               overwritten or removed. machines/, scripts/ and lib/ are read-only
#               in every container; store/ is where a person's data goes
#   handlers:   file-change triggers, [{match, changes, quiet}], each added to
#               .decree/handlers.yml for this machine
#   when:       the kind of note that starts it, in plain words: note_watch asks
#               the model whether a note is that, and emits to this machine
#   cron:       <cron>: <a cron message>, each to .decree/cron/<cron>.md
#   endpoints:  decree-go-rest endpoints, added to .decree/decree-go-rest.yml;
#               each emits to <name> and nothing else
#   needs:      the other plugins it runs or whose lib it uses (export writes it)
#   migrations: <file>: <a migration>, each to .decree/migrations/<file>.md once,
#               after every machine is in, unless it has run
#   project:    which decree project runs it: automation, backup or host, or a
#               list of them. A project installs only what is tagged for it, so
#               nothing the automation daemon can reach ever lands in the others
#   name, tagline, docs, services, e2e, examples: a flow's, read by ./existential.sh
#               flow (services it turns on) and the gates; nothing installs them
# The body says what it is for.
#
# One way in. The repo's automation/plugins/ is the one source, and plugin_sync,
# run on the host by ./existential.sh, is the only thing that installs: every
# container that mounts the workspace has machines/, scripts/ and lib/ read-only.
# A plugin made in the workspace (by develop from a note, by an agent, by another
# stack) is an offer, a file in workspace/ai/proposed/. A person reads it and
# accepts it on the host (./existential.sh run plugin accept <name>), which puts
# it in automation/plugins/local/ (never in git), for the automation project only.
# The plugin system itself (PLUGIN_KERNEL) is a plugin like any other, in every
# project it is tagged for whatever is on, and no accepted plugin can replace it.
# Sourced after registry.sh (REGISTRY, REST, automation_remove). Run from the
# decree project root.

# notify: every machine tells you things, and decree check fails an emits: that
# names a machine the project lacks.
PLUGIN_KERNEL=" notify "

# plugin_src <dir> <name>: the plugin's file: a machine's, a flow's, or one you
# accepted (local/, never in git; a shipped plugin by the same name wins).
plugin_src() {
    if [[ -f "$1/$2.md" ]]; then echo "$1/$2.md"; elif [[ -f "$1/flows/$2.md" ]]; then echo "$1/flows/$2.md"
    elif [[ -f "$1/local/$2.md" ]]; then echo "$1/local/$2.md"; else return 1; fi
}

plugin_is() {  # <message>: true when it carries a chart
    [[ "$(yq --front-matter=extract 'has("chart")' "$1" 2>/dev/null)" == true ]]
}

# Write machine, scripts, lib, crons and endpoints. With a check (the default),
# decree check runs after and any failure puts back what was there; either way a
# failure prints why on stderr.
plugin_install() {  # <name> <message> [spec, as the registry records it] [nocheck]
    local name="$1" msg="$2" spec="${3:-notes/automations/$1.md}" nocheck="${4:-}" fm k e f p fails=()
    fm="${DECREE_RUN_DIR:-${TMPDIR:-/tmp}}/plugin-${name}.yml"
    yq --front-matter=extract '.' "$msg" > "$fm"

    # ── The gate, before anything is written ──────────────────────────────────
    [[ "$PLUGIN_KERNEL" != *" ${name} "* ]] || [[ "$spec" == automation/plugins/* && "$spec" != automation/plugins/local/* ]] ||
        fails+=("${name} is part of the plugin system, which no plugin replaces")
    if [[ "$(yq 'has("chart")' "$fm")" == true ]]; then
        [[ "$(yq '(.chart | tag == "!!map") and (.chart | has("states"))' "$fm")" == true ]] || fails+=("chart must be a machine with states")
    else
        [[ "$(yq '(.scripts // {} | length) == 0 and (.endpoints // [] | length) == 0' "$fm")" == true ]] ||
            fails+=("with no chart it is a flow: no scripts or endpoints, which are a machine's")
    fi
    for p in scripts lib store cron migrations; do
        [[ "$(p="$p" yq '.[strenv(p)] // {} | tag' "$fm")" == '!!map' ]] || fails+=("${p} must be a map of name: text")
    done
    for k in $(yq -r '.scripts // {} | keys | .[]' "$fm"); do
        [[ "$k" =~ ^[a-z][a-z0-9_]{0,40}(\.ts)?$ ]] || fails+=("script name '${k}' is not snake_case")
    done
    for k in $(yq -r '((.cron // {}), (.migrations // {})) | keys | .[]' "$fm"); do
        [[ "$k" =~ ^[a-z0-9][a-z0-9_-]{0,60}$ ]] || fails+=("cron or migration name '${k}' is not a plain file name")
    done
    for k in $(yq -r '.store // {} | keys | .[]' "$fm"); do
        [[ "$k" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ ]] || fails+=("store path '${k}' is not a plain relative path")
    done
    [[ "$(yq '(.handlers // []) | ((tag == "!!seq") and all_c(has("match") and (has("machine") | not)))' "$fm")" == true ]] ||
        fails+=("handlers must be a list of {match, changes, quiet}; the machine is ${name}")
    [[ "$(yq '.when // "" | tag' "$fm")" == '!!str' ]] || fails+=("when must be one line of text")
    for k in $(yq -r '.lib // {} | keys | .[]' "$fm"); do
        [[ "$k" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ ]] || { fails+=("lib path '${k}' is not a plain relative path"); continue; }
        # lib/ is shared: a file there that is not this plugin's is someone else's.
        # (or its <x>.exist.<ext> example, which is how a file of yours shipped before store:)
        e="${k%.*}.exist.${k##*.}"
        [[ ! -e ".decree/lib/${k}" ]] || k="$k" e="$e" n="$name" yq -e '.[] | select(.machine == strenv(n)) | .libs[] | select(. == strenv(k) or . == strenv(e))' "$REGISTRY" >/dev/null 2>&1 ||
            fails+=("lib/${k} is already there, and not this plugin's")
    done
    if [[ "$(yq '.endpoints // [] | length' "$fm")" != 0 ]]; then
        [[ -f "$REST" ]] || fails+=("it has endpoints, and there is no ${REST} (turn on automation-webhook)")
        while IFS=$'\t' read -r k f; do
            [[ "$f" == "$name" ]] || fails+=("endpoint ${k} must emit to ${name}, not '${f}'")
            [[ -f "$REST" ]] && p="$k" yq -e '.endpoints[] | select(.path == strenv(p))' "$REST" >/dev/null 2>&1 &&
                ! p="$k" n="$name" yq -e '.[] | select(.machine == strenv(n)) | .endpoints[] | select(. == strenv(p))' "$REGISTRY" >/dev/null 2>&1 &&
                fails+=("endpoint ${k} is already in ${REST}")
        done < <(yq -r '.endpoints[] | [.path // "", (.action // "emit") as $a | (select($a == "emit") | .message.machine // "") // ("an " + $a + " action")] | @tsv' "$fm")
    fi
    if [[ ${#fails[@]} -gt 0 ]]; then printf -- '- %s\n' "${fails[@]}" >&2; return 1; fi

    # ── Install, keeping what was there so a failed check puts it back ────────
    local backup="${fm%.yml}.previous" touched=(".decree/machines/${name}.yml" ".decree/scripts/${name}" "$REGISTRY" "$REST" "$HANDLERS" "$WATCH")
    for k in $(yq -r '.cron // {} | keys | .[]' "$fm"); do touched+=(".decree/cron/${k}.md"); done
    for k in $(yq -r '.lib // {} | keys | .[]' "$fm"); do touched+=(".decree/lib/${k}"); done
    rm -rf "$backup"; mkdir -p "$backup"
    mkdir -p .decree/machines
    for f in "${touched[@]}"; do [[ -e "$f" ]] && cp -rp "$f" "$backup/$(echo "$f" | tr / _)"; done
    touch "$REGISTRY"
    automation_remove "$name"            # a rebuild starts from nothing

    if [[ "$(yq 'has("chart")' "$fm")" == true ]]; then
        { printf '# Installed from %s. Edit that file, not this one.\n' "$spec"
          n="$name" yq '{"name": strenv(n)} + .chart' "$fm"; } > ".decree/machines/${name}.yml"
    fi
    _plugin_write() {  # <key> <dir> <ext> <mode, or "shebang": 755 when it starts #!>
        local k file
        for k in $(yq -r ".$1 // {} | keys | .[]" "$fm"); do
            file="$2/${k}"; [[ "$k" == *.* ]] || file+="$3"   # gather.ts stays gather.ts
            mkdir -p "$(dirname "$file")"
            printf '%s\n' "$(k="$k" yq -r ".$1[strenv(k)]" "$fm")" > "$file"
            if [[ "$4" != shebang ]]; then chmod "$4" "$file"
            elif [[ "$(head -c2 "$file")" == '#!' ]]; then chmod 755 "$file"; else chmod 644 "$file"; fi
        done
    }
    _plugin_write scripts ".decree/scripts/${name}" .sh 755
    _plugin_write lib ".decree/lib" "" shebang
    # Yours, once: store/<name>/<path>. What an older install kept in lib/ (when
    # this data was lib/<path> or lib/<name>/<path>) moves over instead.
    for k in $(yq -r '.store // {} | keys | .[]' "$fm"); do
        f=".decree/store/${name}/${k}"
        [[ -e "$f" ]] && continue
        mkdir -p "$(dirname "$f")"
        if [[ -f ".decree/lib/${name}/${k}" ]]; then mv ".decree/lib/${name}/${k}" "$f"
        elif [[ -f ".decree/lib/${k}" ]]; then mv ".decree/lib/${k}" "$f"
        else printf '%s\n' "$(k="$k" yq -r '.store[strenv(k)]' "$fm")" > "$f"; fi
    done
    # ...and so does whatever else of yours sat beside it there (a department you added).
    for k in $(yq -r '.store // {} | keys | .[] | select(test("/")) | sub("/[^/]*$"; "")' "$fm" | sort -u); do
        for f in ".decree/lib/${k}"/*; do
            [[ -f "$f" && "$f" != *.exist.* && ! -e ".decree/store/${name}/${k}/${f##*/}" ]] || continue
            yq -e ".[] | .libs[]? | select(. == \"${k}/${f##*/}\")" "$REGISTRY" >/dev/null 2>&1 || mv "$f" ".decree/store/${name}/${k}/"
        done
    done
    # Its triggers: file changes (handlers.yml) and the kind of note (note_watch).
    if [[ "$(yq '.handlers // [] | length' "$fm")" != 0 ]]; then
        touch "$HANDLERS"
        n="$name" yq -i ". = ((. // []) + (load(\"${fm}\").handlers | map({\"match\": .match, \"machine\": strenv(n), \"changes\": (.changes // [\"created\"]), \"quiet\": (.quiet // 30)})))" "$HANDLERS"
    fi
    if [[ -n "$(yq -r '.when // ""' "$fm")" && -f "$WATCH" ]]; then
        n="$name" yq -i '.states.watch.emits = ((.states.watch.emits // []) + [strenv(n)] | unique)' "$WATCH"
    fi
    _plugin_write cron ".decree/cron" .md 644
    [[ "$(yq '.endpoints // [] | length' "$fm")" == 0 ]] || yq -i ".endpoints += load(\"${fm}\").endpoints" "$REST"
    n="$name" s="$spec" yq -i \
        ". = ((. // []) + [{\"machine\": strenv(n), \"kind\": \"plugin\", \"spec\": strenv(s),
            \"endpoints\": (load(\"${fm}\").endpoints // [] | map(.path)),
            \"crons\": (load(\"${fm}\").cron // {} | keys),
            \"libs\": (load(\"${fm}\").lib // {} | keys),
            \"migrations\": (load(\"${fm}\").migrations // {} | keys)}
            + (load(\"${fm}\") | pick([\"when\"]))])" "$REGISTRY"

    [[ -z "$nocheck" ]] || return 0
    local check
    if ! check="$(decree check --no-color 2>&1)"; then
        for f in "${touched[@]}"; do
            rm -rf "$f"
            [[ -e "$backup/$(echo "$f" | tr / _)" ]] && cp -rp "$backup/$(echo "$f" | tr / _)" "$f"
        done
        echo "- decree check: $( { grep -i "$name" <<<"$check" || printf '%s\n' "$check"; } | head -5 | paste -sd ';' -)" >&2
        return 1
    fi
}

# The other way: an installed machine, its scripts, lib, crons and endpoints as
# one plugin file on stdout, which another stack accepts like any plugin. Its
# scripts are found as decree finds them (scripts/<name>/ first). needs: is every
# machine it starts or emits to; what it cannot carry, the $DECREE_LIB files its
# scripts source, is named in the body. An installed plugin keeps its body.
plugin_export() {  # <name>
    local name="$1" m=".decree/machines/$1.yml" out="${DECREE_RUN_DIR:-${TMPDIR:-/tmp}}/export-$1.yml" k f needs libs
    [[ -f "$m" ]] || { [[ -f "$REGISTRY" ]] && automation_installed "$name"; } ||
        { echo "plugin_export: there is no machine ${name}" >&2; return 1; }
    n="$name" m="$m" yq -n '.machine = "plugin" | .automation = strenv(n)' > "$out"
    # A flow's own words and what it turns on are not installed: they come from what it was installed from.
    if [[ -f ".decree/applied/plugins/${name}.md" ]]; then
        yq --front-matter=extract 'pick(["project", "name", "tagline", "docs", "services", "e2e", "examples", "store", "when"])' ".decree/applied/plugins/${name}.md" > "${out}.meta"
        mt="${out}.meta" yq -i '. + load(strenv(mt))' "$out"
    fi
    for k in $( [[ ! -f "$m" ]] || yq -r '[.. | select(tag == "!!map") | ((.invoke | select(tag == "!!str")), (.invoke.script | select(tag == "!!str")),
                .invoke.script.name, .invoke.person.ask, .onentry[]?, .onexit[]?)] | .[] | select(. != null)' "$m" | sort -u); do
        f="$(ls -- ".decree/scripts/${name}/${k}".{sh,ts} ".decree/scripts/${k}".{sh,ts} 2>/dev/null | head -1 || true)"
        [[ -n "$f" ]] || { echo "plugin_export: ${name} runs ${k}, and there is no script for it" >&2; return 1; }
        [[ "$f" == *.sh ]] || k="${k}.${f##*.}"    # gather.ts keeps its extension; .sh is the default
        k="$k" f="$f" yq -i '.scripts[strenv(k)] = load_str(strenv(f))' "$out"
    done
    # Its lib: the files its install wrote (the registry has them).
    if [[ -f "$REGISTRY" ]]; then
        for k in $(n="$name" yq -r '.[] | select(.machine == strenv(n)) | .libs[]?' "$REGISTRY"); do
            [[ -f ".decree/lib/${k}" ]] && K="$k" f=".decree/lib/${k}" yq -i '.lib[strenv(K)] = load_str(strenv(f))' "$out"
        done
    fi
    # Its crons and migrations: an installed plugin's are in the registry; any other
    # machine's crons are the ones that run it.
    if [[ -f "$REGISTRY" ]] && automation_installed "$name"; then
        for k in $(n="$name" yq -r '.[] | select(.machine == strenv(n)) | .crons[]?' "$REGISTRY"); do
            [[ -f ".decree/cron/${k}.md" ]] && K="$k" f=".decree/cron/${k}.md" yq -i '.cron[strenv(K)] = load_str(strenv(f))' "$out"
        done
        for k in $(n="$name" yq -r '.[] | select(.machine == strenv(n)) | .migrations[]?' "$REGISTRY"); do
            if [[ -f ".decree/migrations/${k}.md" ]]; then
                K="$k" f=".decree/migrations/${k}.md" yq -i '.migrations[strenv(K)] = load_str(strenv(f))' "$out"
            elif [[ -f ".decree/applied/plugins/${name}.md" ]]; then   # it ran and is gone: as it was installed
                printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.migrations[strenv(k)]' ".decree/applied/plugins/${name}.md")" > "${out}.mig"
                k="$k" f="${out}.mig" yq -i '.migrations[strenv(k)] = load_str(strenv(f))' "$out"
            fi
        done
    else
        for f in .decree/cron/*.md; do
            [[ -f "$f" && "$(yq --front-matter=extract -r '.machine // ""' "$f" 2>/dev/null)" == "$name" ]] &&
                k="$(basename "$f" .md)" f="$f" yq -i '.cron[strenv(k)] = load_str(strenv(f))' "$out"
        done
    fi
    [[ -f "$HANDLERS" ]] && n="$name" r="$HANDLERS" yq -i \
        '.handlers = [(load(strenv(r)) // [])[] | select(.machine == strenv(n)) | del(.machine)] | del(.handlers | select(length == 0))' "$out"
    [[ -f "$REST" ]] && n="$name" r="$REST" yq -i \
        '.endpoints = [load(strenv(r)).endpoints[] | select((.action // "emit") == "emit" and .message.machine == strenv(n))] | del(.endpoints | select(length == 0))' "$out"
    # The chart, less the machines a note starts (each plugin with a `when:` is
    # added to note_watch's emits when it is installed): they are not the plugin's.
    [[ ! -f "$m" ]] || m="$m" yq -i '.chart = (load(strenv(m)) | del(.name))' "$out"
    [[ ! -f "$REGISTRY" || "$name" != note_watch ]] || r="$REGISTRY" yq -i \
        '(.chart | .. | select(tag == "!!map" and has("emits")) | .emits) -= [load(strenv(r))[] | select(.when) | .machine]' "$out"
    # What it starts or emits to, less itself and the plugin system, which every project has.
    # And every plugin whose lib it uses: ${DECREE_LIB}/model.sh, lib/rss, ../you-were-here/digest.
    # A flow's needs are what it turns on, which nothing here can work out: kept as installed.
    # (No comment inside the $( ): bash 3.2 reads an apostrophe in one as an open quote.)
    needs="$( { yq -r '[.chart // {} | .. | select(tag == "!!map") | (.invoke.machine, .emits[]?) | select(tag == "!!str")] | .[]' "$out"
                yq -r '(.scripts // {})[], (.lib // {})[]' "$out" | grep -oE 'emit --machine [a-z_][a-z0-9_]*' | sed 's/.* //'
                [[ ! -f "$REGISTRY" ]] || _plugin_lib_users "$out"
                [[ -f "$m" || ! -f ".decree/applied/plugins/${name}.md" ]] ||
                    yq --front-matter=extract -r '.needs // [] | .[]' ".decree/applied/plugins/${name}.md"
              } | grep -v '^$' | grep -vxF "$name" | while read -r k; do [[ "$PLUGIN_KERNEL" == *" ${k} "* ]] || echo "$k"; done |
              if [[ -f "$m" ]]; then sort -u; else awk '!seen[$0]++'; fi || true)"
    [[ -z "$needs" ]] || v="$(paste -sd, - <<<"$needs")" yq -i '.needs = (strenv(v) | split(","))' "$out"
    # In reading order: what it is, the machine, what the machine runs, how it is reached.
    yq -i 'pick(["machine", "automation", "project", "name", "tagline", "docs", "services", "needs", "e2e", "when", "chart", "scripts", "lib", "store", "cron", "handlers", "migrations", "endpoints", "examples"])
        | with_entries(select(.value != null))' "$out"
    libs="$(yq -r '.scripts[]?' "$out" | grep -o 'DECREE_LIB}/[A-Za-z0-9_./-]*' | while read -r f; do [[ "$(yq -r ".lib[\"${f#DECREE_LIB}/}\"] // \"\"" "$out")" ]] || echo "$f"; done | sed 's#^DECREE_LIB}/#- $DECREE_LIB/#' | sort -u || true)"
    printf -- '---\n'; cat "$out"; printf -- '---\n'
    if [[ -f ".decree/applied/plugins/${name}.md" ]]; then
        awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; b=1; next} b' ".decree/applied/plugins/${name}.md"
    else
        printf '# %s\n\n%s\n' "$name" "$( [[ ! -f "$m" ]] || yq -r '.description // ""' "$m")"
        [[ -z "$libs" ]] || printf '\nIt needs, on the stack that installs it:\n\n%s\n' "$libs"
    fi
}

# _plugin_lib_users <exported plugin yml>: each installed plugin whose lib its
# scripts or lib name, as a source line or an import would.
_plugin_lib_users() {
    local text owner path stem
    text="$(yq -r '(.scripts // {})[], (.lib // {})[]' "$1")"
    while IFS=$'\t' read -r owner path; do
        stem="${path%.*}"
        grep -qE "(LIB\}?|lib|\.|\))/(${path//./\\.}|${stem//./\\.})([^A-Za-z0-9_./-]|$)" <<<"$text" && echo "$owner"
    done < <(yq -r '.[] | select(.kind == "plugin") | .machine as $m | .libs[]? | [$m, .] | @tsv' "$REGISTRY")
    return 0
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
# installed there as written and unchecked, beside the plugin system's lib: a
# test's or the gate's scratch project. A plugin's scripts are then
# <root>/.decree/scripts/<name>/<script>.sh, and DECREE_LIB is <root>/.decree/lib.
plugin_unpack() {
    local root="${!#}" lib dir n
    lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; dir="$(cd "${lib}/../plugins" && pwd)"
    mkdir -p "${root}/.decree/lib"
    cp -rp "${lib}/." "${root}/.decree/lib/"
    ( cd "$root" && { [[ -f "$REST" ]] || echo 'endpoints: []' > "$REST"; }
      export DECREE_RUN_DIR="${DECREE_RUN_DIR:-$(mktemp -d)}"
      for n in $(plugin_wanted "$dir" none "${@:1:$#-1}"); do
          automation_installed "$n" && cmp -s "$(plugin_src "$dir" "$n")" ".decree/applied/plugins/${n}.md" && continue
          src="$(plugin_src "$dir" "$n")"
          plugin_install "$n" "$src" "automation/plugins/${src#"${dir}/"}" nocheck || return 1
          mkdir -p .decree/applied/plugins; cp "$src" ".decree/applied/plugins/${n}.md"
      done )
}

# What a plugin installs, as one line of sorted JSON: two files that would
# install the same thing compare equal.
plugin_canon() {  # <file>
    yq --front-matter=extract -o=json -I=0 'pick(["chart", "scripts", "lib", "cron", "handlers", "when", "migrations", "endpoints"]) | sort_keys(..)' "$1"
}

# ── The repo's plugins: what a project has on, kept current ───────────────────
#
# <dir>/../plugins.yml (automation/plugins.yml, never in git; PLUGINS_ON names
# another) is the one record of what is on, for every project, written from
# plugins.exist.yml the first time (src/utils/flows.sh):
#   on: [name, ...]        machines and flows; what they need comes with them
#   auto_update: true      false: a changed plugin is listed, not installed

# plugin_tags <file>: the projects that run it, one per line (none: automation).
plugin_tags() { yq --front-matter=extract -r '[.project // "automation"] | flatten | .[]' "$1"; }

# plugin_wanted <dir> <project> [name...]: every plugin the project should have,
# each once: what is on, the plugin system and the names given, and all they
# need, less whatever is not tagged for this project. Project `none` is a scratch
# project: the names given and all they need, whatever their tags.
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
        src="$(plugin_src "$dir" "$n")" || { echo "plugin: no plugin ${n} in ${dir}" >&2; continue; }
        seen+="${n} "
        [[ "$project" == none ]] || plugin_tags "$src" | grep -qxF "$project" || continue
        # One you accepted from the workspace runs in the automation project and nowhere else.
        [[ "$src" != */local/* || "$project" == automation || "$project" == none ]] || continue
        echo "$n"
        while IFS= read -r f; do [[ -n "$f" ]] && queue+=("$f"); done < <(yq --front-matter=extract -r '.needs // [] | .[]' "$src")
    done
}

# plugin_sync <dir> <project> [name...]: install each wanted plugin that is new
# or whose file changed since it was installed, and remove each one that is no
# longer wanted. An installed copy edited by hand (or one copied in before
# plugins, by the same name) is kept in .decree/archive/ first. Machines that
# are not the repo's plugins (yours, develop's, an accepted one) are never touched.
# One decree check at the end: the plugins are checked together, as they run.
plugin_sync() {
    local dir="$1" project="$2" wanted n src applied ref auto rc=0 keep check
    shift 2
    wanted=" $(plugin_wanted "$dir" "$project" "$@" | tr '\n' ' ') "
    # Not `// true`: yq's alternative treats false as missing.
    auto="$(yq '.auto_update' "${PLUGINS_ON:-${dir}/../plugins.yml}" 2>/dev/null || echo true)"
    keep=".decree/archive/$(date +%Y%m%d-%H%M%S)"
    mkdir -p .decree/applied/plugins .decree/machines .decree/scripts .decree/cron .decree/archive
    touch "$REGISTRY"
    for n in $wanted; do
        src="$(plugin_src "$dir" "$n")" applied=".decree/applied/plugins/${n}.md"
        cmp -s "$src" "$applied" && automation_installed "$n" &&
            { [[ -f ".decree/machines/${n}.yml" ]] || ! plugin_is "$src"; } && continue
        if [[ -f "$applied" && "$auto" == false ]]; then echo "plugin: ${n} has a new version (auto_update is off)"; continue; fi
        if [[ -f ".decree/machines/${n}.yml" ]] || automation_installed "$n"; then
            ref="$applied"; [[ -f "$ref" ]] || ref="$src"
            if [[ "$(plugin_export "$n" 2>/dev/null > "${keep}.export" && plugin_canon "${keep}.export")" != "$(plugin_canon "$ref")" ]]; then
                mkdir -p "${keep}/scripts"
                cp -p ".decree/machines/${n}.yml" "$keep/" 2>/dev/null || true
                cp -rp ".decree/scripts/${n}" ".decree/scripts/${n}.sh" "${keep}/scripts/" 2>/dev/null || true
                for f in $(n="$n" yq -r '.[] | select(.machine == strenv(n)) | .libs[]?' "$REGISTRY"); do
                    mkdir -p "$(dirname "${keep}/lib/${f}")"; cp -p ".decree/lib/${f}" "${keep}/lib/${f}" 2>/dev/null || true
                done
                if automation_installed "$n"; then echo "plugin: your edit of ${n} is replaced by the new version; it is kept in ${keep}/"
                else echo "plugin: ${n} from before plugins is replaced by the plugin; the old copy is kept in ${keep}/"; fi
            fi
            # Not the registry's (copied in before plugins): its endpoints are the plugin's now.
            automation_installed "$n" || { [[ -f "$REST" ]] && n="$n" yq -i 'del(.endpoints[] | select(.message.machine == strenv(n)))' "$REST"; }
            rm -f ".decree/machines/${n}.yml" ".decree/scripts/${n}.sh"; rm -rf ".decree/scripts/${n}"
        fi
        if plugin_install "$n" "$src" "automation/plugins/${src#"${dir}/"}" nocheck; then
            cp "$src" "$applied"; echo "plugin: ${n} installed"
        else
            echo "plugin: ${n} was not installed" >&2; rc=1
        fi
    done
    rm -f "${keep}.export"
    # A note_watch installed again: every installed plugin a note starts is put back in its emits.
    [[ ! -f "$WATCH" ]] || r="$REGISTRY" yq -i \
        '.states.watch.emits = ((.states.watch.emits // []) + [load(strenv(r))[] | select(.when) | .machine] | unique)' "$WATCH"
    # Migrations last, once every machine is in: a daemon that sees one before its
    # machine fails it. Each is written once and never again after it has run.
    for n in $wanted; do
        src="$(plugin_src "$dir" "$n")"
        for k in $(yq --front-matter=extract -r '.migrations // {} | keys | .[]' "$src"); do
            [[ -e ".decree/migrations/${k}.md" ]] && continue
            grep -qxF "${k}.md" .decree/processed.md 2>/dev/null && continue
            mkdir -p .decree/migrations
            printf '%s\n' "$(k="$k" yq --front-matter=extract -r '.migrations[strenv(k)]' "$src")" > ".decree/migrations/${k}.md"
            echo "plugin: ${n}'s migration ${k} is queued"
        done
    done
    for n in $(yq -r '.[] | select(.kind == "plugin" and (.spec | test("^automation/plugins/"))) | .machine' "$REGISTRY"); do
        [[ "$wanted" == *" ${n} "* ]] && continue
        # A migration that has not run goes with it; one that ran is history.
        for k in $(n="$n" yq -r '.[] | select(.machine == strenv(n)) | .migrations[]?' "$REGISTRY"); do
            grep -qxF "${k}.md" .decree/processed.md 2>/dev/null || rm -f ".decree/migrations/${k}.md"
        done
        automation_remove "$n"; rm -f ".decree/applied/plugins/${n}.md"
        echo "plugin: ${n} removed"
    done
    # Before plugins every shipped machine was copied in. One by a plugin's name
    # that nothing wants and nothing installed is that copy: kept, then removed.
    for src in "$dir"/*.md; do
        n="$(basename "$src" .md)"
        [[ -f ".decree/machines/${n}.yml" && "$wanted" != *" ${n} "* ]] && ! automation_installed "$n" || continue
        mkdir -p "${keep}/scripts"
        mv ".decree/machines/${n}.yml" "$keep/"
        mv ".decree/scripts/${n}" ".decree/scripts/${n}.sh" "${keep}/scripts/" 2>/dev/null || true
        [[ ! -f "$REST" ]] || n="$n" yq -i 'del(.endpoints[] | select(.message.machine == strenv(n)))' "$REST"
        echo "plugin: ${n}, copied in before plugins and not on, is removed (kept in ${keep}/)"
    done
    if command -v decree >/dev/null 2>&1 && ! check="$(decree check --no-color 2>&1)"; then
        echo "plugin: decree check fails after the sync:" >&2; printf '%s\n' "$check" | head -20 >&2; rc=1
    fi
    return $rc
}
