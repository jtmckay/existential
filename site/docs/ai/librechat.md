---
sidebar_position: 1
---

# LibreChat

- Source: https://github.com/danny-avila/LibreChat
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: ChatGPT UI, OpenWebUI, GPT4All, Chatbot UI

## Features

- **Multi-Provider Support**: OpenAI, Azure, Anthropic, Google, and custom endpoints
- **Plugin System**: Extensible with custom plugins and integrations
- **Conversation Management**: Organize chats with folders and search functionality
- **User Authentication**: Secure multi-user environment with role-based access
- **Model Switching**: Switch between different AI models within conversations
- **File Uploads**: Support for document analysis and image processing
- **Custom Presets**: Save conversation settings and system prompts
- **Message Export**: Download conversations in various formats

## Getting Started

### Generate password hash

Replace `SUPER_SECURE_PASSWORD` with your password:

```bash
docker run --rm node:20-alpine sh -c 'mkdir /app && cd /app && npm init -y >/dev/null && npm install bcryptjs >/dev/null && node -e "console.log(require(\"bcryptjs\").hashSync(\"SUPER_SECURE_PASSWORD\", 10))"'
```

### Add a user via MongoDB

```bash
docker exec -it librechat-mongodb mongosh
```

```js
use LibreChat
db.users.insertOne({
  email: "admin@example.com",
  password: "<PASTE_HASH>",
  role: "ADMIN",
  emailVerified: true,
  createdAt: new Date(),
  updatedAt: new Date()
})
```

### Add Google Search tool

Fill out these `.env` values following the [LibreChat docs](https://www.librechat.ai/docs/configuration/tools/google_search):

```
GOOGLE_SEARCH_API_KEY=
GOOGLE_CSE_ID=
```

### Add agents

Create agents (with "file search" capability) for use with Windmill scripts. After creating, the `agent_id` appears at the top of the side panel.

## Debugging

```bash
# View logs
docker compose exec librechat-api sh -lc 'cat /app/api/data/logs.json'

# View violations/bans
docker compose exec librechat-api sh -lc 'cat /app/api/data/violations.json'

# Find MongoDB user ID
docker exec -it librechat-mongodb mongosh
use LibreChat
db.user.find()
```
