---
sidebar_position: 7
---

# Mealie

- Source: https://github.com/mealie-recipes/mealie
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.en.html)
- Alternatives: Tandoor Recipes, RecipeSage, Grocy, Paprika

## Getting Started

Enable it, then bring the stack up from the repo root:

```bash
EXIST_IS_SERVICES_MEALIE=true    # in .env.shared
./existential.sh && docker compose up -d
```

On first launch, change the username and password for the default account manually.
