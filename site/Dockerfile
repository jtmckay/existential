# Image for running the Existential documentation site (Docusaurus).
#
# Dependencies are baked into the image so the dev server starts fast and
# reproducibly; the source is bind-mounted at runtime (see docker-compose.yml)
# for live reload.

# Docusaurus 3 requires Node >= 20. @docusaurus/faster ships native (glibc)
# binaries — use the Debian-based image, not Alpine/musl.
FROM node:22-bookworm-slim

WORKDIR /app
# The node image ships a `node` user at uid 1000 (matches a typical host user),
# so cache files written back through the bind mount stay host-owned, not root.
RUN chown node:node /app
USER node

# Install from the lockfile first so this layer caches across source edits.
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci

EXPOSE 3000

# Dev server. --poll makes file watching work across the bind mount; --host
# exposes it outside the container; --no-open skips the (absent) browser.
CMD ["npm", "run", "start", "--", "--host", "0.0.0.0", "--port", "3000", "--no-open", "--poll", "1000"]
