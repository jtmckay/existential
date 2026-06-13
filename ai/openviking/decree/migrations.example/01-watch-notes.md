---
routine: openviking-watch-dirs
WATCH_DIRS: |
  file:///app/notes
  file:///app/resources
---

Register /app/notes and /app/resources as watched directories in OpenViking.
OpenViking will automatically re-index files when they change (every 300s).

Add or remove entries from WATCH_DIRS to adjust which directories are watched.
Each line must be a file:// URI accessible inside the openviking container.

Run once after the container is healthy. Copy to decree/migrations/ to activate.
