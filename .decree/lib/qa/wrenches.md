# Wrenches

Ways to make the project misbehave. qa's tests each name one. Add the project's own.

- W1 Input boundaries: empty, one, huge, negative, zero, non-ASCII, wrong type, malformed.
- W2 Repetition: the same action twice, fast; double submit; repeat until a limit.
- W3 Ordering: steps out of order, back and forward, an action before setup is done.
- W4 Interruption: a crash or kill mid-write, then a restart.
- W5 Resources: disk or quota full, no network, a slow or failing service, a timeout.
- W6 Corrupt state: saved data truncated, garbled, from an older version, or missing.
- W7 Concurrency: two users or processes acting on the same thing at once.
- W8 Time: clock changes, time zones and daylight saving, dates far in the past or future.
