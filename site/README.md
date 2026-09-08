# Website

This website is built using [Docusaurus](https://docusaurus.io/), a modern static website generator.

## Installation

```bash
yarn
```

## Local Development

```bash
yarn start
```

This command starts a local development server and opens up a browser window. Most changes are reflected live without having to restart the server.

### Without Node/npm (Docker)

The `Dockerfile` here bakes in `npm ci` so the dev server starts fast; the source is
bind-mounted at runtime for live reload (`--poll` in the `CMD` makes file watching work across
the bind mount). An anonymous volume on `node_modules` keeps the container's own install
(native `@docusaurus/faster` binaries) from being shadowed by the host's `site/node_modules`.

```bash
cd site && docker compose up
```

Builds the image on first run only (cached after), starts the dev server, and hot-reloads on
file changes. Then open http://localhost:3030 (mapped to the container's port 3000).
`docker compose up --build` forces a rebuild after a `package.json`/`package-lock.json` change.

## Build

```bash
yarn build
```

This command generates static content into the `build` directory and can be served using any static contents hosting service.

## Deployment

Using SSH:

```bash
USE_SSH=true yarn deploy
```

Not using SSH:

```bash
GIT_USER=<Your GitHub username> yarn deploy
```

If you are using GitHub pages for hosting, this command is a convenient way to build the website and push to the `gh-pages` branch.
