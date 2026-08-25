---
sidebar_position: 3
---

# Vikunja

- Source: https://github.com/go-vikunja/vikunja
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Todoist, Notion, TickTick, Tasks.org
- Status: RIP — replaced by the [Obsidian Kanban plugin](../../services/obsidian#kanban)

Self-hosted task manager with projects, kanban boards, reminders, and a CalDAV bridge. It
worked; it was simply more machinery than the job needed — a container, a database, a Caddy
hostname, and a backup sidecar to keep tasks that now live as markdown in the notes vault.

## If you still want it

The service files are kept under `graveyard/vikunja/`: `docker-compose.yml.example`,
`.env.example`, its `exist.test.sh`, and the decree sidecar's backup crons and default-user
migration. Nothing was deleted — but it is no longer wired into `./existential.sh`, Caddy,
Dashy, or the quests, so re-enabling it means restoring those by hand.

Existing data is untouched. Volumes stay at `volumes_local/vikunja_data/` and any backups at
`volumes/vikunja_data_backup/` until you remove them yourself.
