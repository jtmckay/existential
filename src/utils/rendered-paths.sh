#!/usr/bin/env bash
# rendered-paths.sh — sourced only. The inverse of src/templates.sh's
# _template_to_dst: given a path, name the *.exist.* template that would render
# INTO it, if one exists.
#
# This is what makes "is this file rendered?" answerable without a list of
# extensions to maintain. Both secret guards (.githooks/pre-commit and
# src/test/no-tracked-secrets.sh) key off it: a rendered file carries whatever
# secrets its template's placeholders resolved to, so a sibling template is the
# tell that a file must never be tracked. Keeping the rule here means the two
# guards cannot drift apart, and a new rendered file type is covered the day it
# is added rather than the day someone remembers to extend a case statement.
#
# Mirrors all three template spellings templates.sh understands:
#   foo.exist.json      -> foo.json
#   Caddyfile.exist.Caddyfile -> Caddyfile   (before == after)
#   .env.exist          -> .env

# template_for_rendered <path>
# Prints the template path and returns 0 if one exists on disk; returns 1 otherwise.
template_for_rendered() {
    local path="$1" dir base stem ext candidate
    dir="$(dirname -- "$path")"
    base="$(basename -- "$path")"

    for candidate in \
        "${dir}/${base}.exist" \
        "${dir}/${base}.exist.${base}"
    do
        if [ -e "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
    done

    # foo.json -> foo.exist.json. Only when there is a real stem AND extension,
    # so a dotfile like .env does not become ".exist.env".
    if [[ "$base" == *.* ]]; then
        stem="${base%.*}"
        ext="${base##*.}"
        if [ -n "$stem" ] && [ -n "$ext" ]; then
            candidate="${dir}/${stem}.exist.${ext}"
            if [ -e "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
        fi
    fi

    return 1
}
