---
name: Notifications (ntfy)
tagline: Connect Decree and other services to your ntfy notification channel
e2e: false
services:
  - var: EXIST_IS_SERVICES_NTFY
    label: ntfy
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
---

ntfy provides push notifications to any device. Decree and other services send
alerts through it, and it sets itself up — there is no token to mint and nothing
to copy between screens.

── What already happened ────────────────────────────────────────────────

On its first boot ntfy created two users from your generated credentials:

  your admin login   services/ntfy/.env — NTFY_ADMIN_USER / NTFY_ADMIN_PASSWORD
  the publisher      .env.shared — EXIST_NTFY_USER / EXIST_NTFY_PASSWORD

Decree publishes as the bot over basic auth. ntfy denies every publish by
default (auth-default-access: deny-all), so the bot is the reason anything is
delivered at all — and it is a plain user scoped to EXIST_NTFY_TOPICS, not an
admin.

── Step 1: Subscribe ────────────────────────────────────────────────────

1. Install the ntfy app, or open https://ntfy.x.internal in a browser.
2. Sign in with the admin credentials above.
3. Subscribe to the "decree" topic — that is where routines report by default.
   Individual routines can override it with `ntfy_topic:` in their frontmatter.

── Step 2: Test a notification ──────────────────────────────────────────

  ./existential.sh test ntfy

Or send one by hand as the bot:

  curl -u "$EXIST_NTFY_USER:$EXIST_NTFY_PASSWORD" \
       -d "Hello from existential" \
       http://ntfy.x.internal/decree

── Optional: use a bearer token instead ─────────────────────────────────

  ./existential.sh run ntfy setup

Mints a token for the bot and writes EXIST_NTFY_TOKEN to .env.shared. A token
takes precedence over the user/password wherever both are set. You do not need
this — it exists for sharing publish access without sharing the password.

Telegram fallback:
  If ntfy rejects the publish or is unreachable, Decree falls back to Telegram
  if configured. See the auto-telegram quest.
