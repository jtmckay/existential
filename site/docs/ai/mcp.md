---
sidebar_position: 4
---

# MCP (Playwright)

- Source: https://github.com/microsoft/playwright-mcp
- License: Apache 2.0

Model Context Protocol server that exposes a headless Chromium browser to any MCP-compatible AI agent. Allows agents to navigate pages, click, fill forms, screenshot, and scrape — without writing custom browser automation code.

## Port

| Service | Port |
|---|---|
| MCP server | 8931 |

## Usage

Point any MCP-compatible client (Claude, Hermes, etc.) at `http://mcp-playwright:8931` over the `exist` network. The server exposes browser control as MCP tools the model can call directly.

## Debugging

```bash
docker compose logs mcp-playwright
```
