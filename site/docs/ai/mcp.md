---
service: ai/mcp
sidebar_position: 4
---

# MCP (Playwright)

- Source: https://github.com/microsoft/playwright-mcp
- License: Apache 2.0

An MCP server that gives agents a headless Chromium browser: navigate, click, fill forms, screenshot, scrape.

## Port

| Service | Port |
|---|---|
| MCP server | 8931 |

## Usage

Point any MCP-compatible client (Claude, pi, etc.) at `http://mcp-playwright:8931/mcp` over the `exist` network. The server exposes browser control as MCP tools the model can call directly.

There is no login, and it is a browser that can reach every other container, so it is reachable
only on the `exist` network: no Caddy name, no published port. Don't add either.

## Debugging

```bash
docker compose logs mcp-playwright
```
