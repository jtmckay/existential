---
sidebar_position: 7
---

# Mealie

- Source: https://github.com/mealie-recipes/mealie
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.en.html)
- Alternatives: Tandoor Recipes, RecipeSage, Grocy, Paprika

[Mealie](https://mealie.io/) is a self-hosted recipe manager, meal planner, and shopping-list
app. Import recipes by pasting a URL (it scrapes the page's structured recipe data) or enter
them by hand; organize them into cookbooks, plan meals on a calendar, and generate a shopping
list from the plan.

## Getting Started

Enable it, then bring the stack up from the repo root:

```bash
EXIST_IS_SERVICES_MEALIE=true    # in .env.shared
./existential.sh && docker compose up -d
```

Signup is disabled (`ALLOW_SIGNUP=false`) — there's just the one default account mealie creates
on first boot:

- Email: `changeme@example.com`
- Password: `MyPassword`

Log in at `https://mealie.<domain>` and change both immediately in **Settings > User Profile**.

## AI Recipe Parsing (optional, manual)

Mealie can use an LLM to parse a recipe from a pasted image, or to transcribe and structure a
recipe from a video/audio URL. As of the version this stack ships (v3.23.1), upstream moved this
out of environment variables entirely — the whole feature is configured through **Admin >
AI Providers** in the UI and stored per-group in Mealie's own database, not in this service's
compose file or `.env`. There is nothing here for `.env.exist.shared`'s model-role keys to wire
into, so this is a manual, one-time step if you want it:

1. Log in as an admin and go to **Admin > AI Providers**.
2. Add a provider pointing at this stack's ollama over Docker DNS:
   - Base URL: `http://ollama:11434/v1`
   - API key: anything non-empty — ollama doesn't check it (`ollama` works)
   - Model: whatever this stack's `.env.shared` currently has for `EXIST_MODEL_CHAT` (text
     parsing) or `EXIST_MODEL_VISION` (image parsing) — both point at the same tag by default
   - Assign it as the **Default** provider (text) and/or **Image** provider
3. The **Audio** provider role needs an OpenAI-compatible `/v1/audio/transcriptions` endpoint.
   This stack's `ai/whisperx` exposes exactly that at `http://whisperx:8000/v1` when enabled —
   untested end-to-end against Mealie's audio-import flow, but worth trying if you want that role
   filled too.

Because this is UI/DB config rather than an env var, it does **not** get reset by
`./existential.sh` or survive a `reset` — it lives in the `mealie_pg_data` volume like everything
else you enter in the app.
