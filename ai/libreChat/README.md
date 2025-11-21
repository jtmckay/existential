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

### Getting started

#### Generate the password hash for your password (replace SUPER_SECURE_PASSWORD)

`docker run --rm node:20-alpine sh -c 'mkdir /app && cd /app && npm init -y >/dev/null && npm install bcryptjs >/dev/null && node -e "console.log(require(\"bcryptjs\").hashSync(\"SUPER_SECURE_PASSWORD\", 10))"'`

#### Run one command at a time in a terminal to add a user:

```sql
docker exec -it librechat-mongodb mongosh
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

IF NOT USING ./existential.sh script: generate credentials and replace all .env secrets: https://www.librechat.ai/toolkit/creds_generator?utm_source=chatgpt.com

#### Add tools

To add google search as a tool, fill out these .env values following https://www.librechat.ai/docs/configuration/tools/google_search
GOOGLE_SEARCH_API_KEY=
GOOGLE_CSE_ID=

#### Add agents

Create agents, likely just with "file search" capability, for use with Windmill scripts. After creating you can get the agent_id at the top of the side panel.

### Debugging

Helpful commands when troubleshooting illegal action / violation / bans.

- `docker compose exec librechat-api sh -lc 'cat /app/api/data/logs.json'`
- `docker compose exec librechat-api sh -lc 'cat /app/api/data/violations.json'`

Find your mongo UserID

- `docker exec -it librechat-mongodb mongosh`
- `use LibreChat`
- `db.user.find()`
