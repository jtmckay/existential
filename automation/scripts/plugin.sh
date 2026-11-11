#!/usr/bin/env bash
# plugin — install a plugin you accepted.
#
# The migration is the plugin file (notes/automations/<name>.md, filed by
# reconcile): its frontmatter carries the machine, scripts, lib, crons and
# endpoints, installed as written with no model asked (lib/automations/plugin.sh).
# A failed decree check puts back what was there. The repo's own plugins are not
# installed here: ./existential.sh syncs those (run plugin).
set -euo pipefail
# shellcheck source=../lib/automations/registry.sh
source "${DECREE_LIB}/automations/registry.sh"
# shellcheck source=../lib/automations/plugin.sh
source "${DECREE_LIB}/automations/plugin.sh"

name="${DECREE_DATA_AUTOMATION:-$(yq --front-matter=extract -r '.automation // ""' "$DECREE_MESSAGE")}"
[[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "plugin: '${name}' is not a machine name" >&2; exit 1; }
if [[ -e ".decree/machines/${name}.yml" ]] && ! automation_installed "$name"; then
    echo "plugin: ${name} is a machine this stack ships or you wrote; refusing to replace it" >&2; exit 1
fi
plugin_is "$DECREE_MESSAGE" || { echo "plugin: ${name} carries no chart, so it is not a plugin" >&2; exit 1; }

plugin_install "$name" "$DECREE_MESSAGE" || { echo "plugin: ${name} was not installed" >&2; exit 1; }
# What it was installed from, so reconcile can tell an edit from no change.
migration="$(cd .decree/migrations && ls -- A*-"${name}".md 2>/dev/null | head -1 || true)"
if [[ -n "$migration" ]]; then mkdir -p .decree/applied; cp ".decree/migrations/${migration}" ".decree/applied/${migration}"; fi
echo "plugin: installed ${name}"
printf '%s is installed from notes/automations/%s.md.\n' "$name" "$name" |
    "${DECREE:-decree}" emit --machine notify --param ntfy_title="Plugin installed" --param ntfy_tags=robot >/dev/null
