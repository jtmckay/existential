---
name: file-advice
x-exist-project: automation
x-exist-title: Advice on what you save
x-exist-tagline: Each file you add from now on is read once, and your phone hears which flow (or new machine) would handle it
x-exist-docs: /docs/flows#file-advice
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - file_advise
---

Claude reads each file once you sign in (claude, then /login, in code-server's terminal);
without that, the chat model; with neither, nothing happens. What is in the workspace when it is turned on is
marked as handled without being read; from then on each new or changed file is read once.
volumes/workspace_data/.decree/store/file_advise/ has handled.txt (delete a line to read that
file again) and suggested.txt (delete a line to hear that suggestion again).
