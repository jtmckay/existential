---
machine: e2e_file_handlers
e2e_check: 20-file-handlers
requires: EXIST_IS_SERVICES_AUTOMATION
---

A file written in the workspace → the `automation` container's file-handlers
watcher → `.decree/handlers.yml` → a run of the handler's machine, with `path`
and `change`.

This is Core's own trigger, with no Nextcloud in the loop: whoever writes the
file (code-server, a sync, a script), the matching machine runs once the file
has been quiet. It asks the three things a person would notice:

- a matching file queues exactly one run, however many times it was saved
  while being written;
- a file a `.gitignore` covers queues nothing, whatever the handler matches;
- the run it queues is the handler's machine, and gets the path and the change.

The handler's machine is this check's own machine: run with a `path`, its
script is the probe and checks the params it was given; run without one, it is
the check. The probe's run is graded like every other run in the clone, so a
handler that queued a run nothing could execute fails there.
