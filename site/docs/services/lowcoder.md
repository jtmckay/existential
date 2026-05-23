---
sidebar_position: 11
---

# Lowcoder

- Source: https://github.com/lowcoder-org/lowcoder
- License: [AGPL-3.0](https://github.com/lowcoder-org/lowcoder/blob/main/LICENSE)
- Alternatives: Appsmith, Retool, Tooljet
- UI: `http://localhost:43000`

Low-code platform for building internal and customer-facing apps. Continuation of the abandoned Openblocks project. Better suited for customer-facing / external apps than [Appsmith](./appsmith) (prettier UI, native embedding).

## Features

- **Visual UI Builder**: 120+ components with drag-and-drop editor
- **Native Embedding**: Embed apps in websites without iframes
- **Data Connections**: PostgreSQL, MongoDB, MySQL, Redis, REST, WebSocket
- **JavaScript throughout**: Escape hatch to JS anywhere in the builder
- **RBAC**: Role-based access control
- **Version History**: Auto-saved with full history
- **App Theming**: Consistent styling across apps

## Services

| Container | Purpose |
|---|---|
| lowcoder-frontend | Web UI (port 43000) |
| lowcoder-api-service | API backend |
| lowcoder-node-service | Node script execution |
| lowcoder-mongodb | Storage |
| lowcoder-redis | Cache |
