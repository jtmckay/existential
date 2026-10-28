---
sidebar_position: 1.5
---

# Your Own Newsletter

A weekly issue from feeds you picked, chosen by a paragraph you wrote. At most seven items, or
one line saying there was nothing.

Needs Core plus a chat model ([Model endpoints](../configuration#endpoints--putting-roles-on-different-machines)).

## What it does

Every Monday at 07:00 the `newsletter` machine:

1. **gathers** new items from every feed in `automation/lib/newsletter/feeds.txt`, skipping
   any link it has sent before;
2. **writes** the issue: the chat model reads `automation/lib/newsletter/taste.md` and picks
   from the new items by it, one line each, best first;
3. **delivers** it to `workspace/newsletter/<date>.md` and sends its first lines to ntfy.

A link is never in two issues: the machine remembers every one it has sent, in its store.

## Set it up

1. List your feeds in `automation/lib/newsletter/feeds.txt`, one RSS or Atom URL per line.
   A feed that fails is skipped that week.
2. Write what you want in `automation/lib/newsletter/taste.md`: what you care about, what to
   skip, how long the issue should be.
3. Turn the schedule on:

   ```bash
   ./existential.sh flow on newsletter
   ```

   Run one now from code-server's terminal with `cd /workspace && echo | decree emit
   --machine newsletter`.

Both files are re-read on every run, so an edit applies to the next issue.

## Related

The morning [you were here](../getting-started#you-were-here) digest has its own short list
from `workspace/notes/feeds.md`: the few new items closest to what you were working on.
