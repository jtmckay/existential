FROM rust:slim-bookworm AS builder
RUN cargo install decree --version 0.4.2

FROM debian:bookworm-slim
ENV NODE_VERSION=24.16.0
COPY --from=builder /usr/local/cargo/bin/decree /usr/local/bin/decree
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        poppler-utils curl jq dnsutils xz-utils fzf \
        postgresql-client default-mysql-client sqlite3 gnupg ca-certificates \
    && curl -fsSL https://downloads.rclone.org/rclone-current-linux-amd64.deb -o /tmp/rclone.deb \
    && dpkg -i /tmp/rclone.deb \
    && rm /tmp/rclone.deb \
    && curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
        | gpg --dearmor -o /usr/share/keyrings/mongodb-org-7.0.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/mongodb-org-7.0.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" \
        > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends mongodb-database-tools \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && npm install -g npm@11.16.0 \
    && rm -rf /var/lib/apt/lists/*
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml /opt/decree/
# Reproducible, integrity-checked install via pnpm (version pinned by package.json's
# packageManager field, provisioned by corepack). The committed pnpm-lock.yaml pins the
# full tree; --frozen-lockfile fails the build if package.json drifts from it. pnpm runs
# NO dependency build scripts except the allowlist in package.json's
# pnpm.onlyBuiltDependencies (better-sqlite3, esbuild) — closing the install-script
# supply-chain hole that `npm install` left open. node-linker=hoisted (.npmrc) keeps the
# flat node_modules layout that NODE_PATH below relies on.
RUN cd /opt/decree \
    && corepack enable \
    && pnpm install --frozen-lockfile --prod
ENV NODE_PATH=/opt/decree/node_modules
ENV PATH=/opt/decree/node_modules/.bin:$PATH
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# Daemon services mount their project at /work/.decree and don't set DECREE_DIR,
# so `decree daemon` must run from /work to detect the project. Without this the
# daemon dies with "not inside a decree project".
WORKDIR /work
# Liveness for the no-network decree daemon (main + every *-decree sidecar).
# After entrypoint.sh `exec decree daemon`, PID 1's comm is "decree". A stale
# or mis-built image (no ENTRYPOINT → base CMD "bash") fails this check, and a
# dead daemon stops being PID 1 — both surface as (unhealthy) in `docker ps`.
# start-period is generous because sidecars spend up to DECREE_MIGRATE_TIMEOUT
# (default 300s) running the health-wait loop as bash before exec-ing the daemon;
# during that window the check fails but stays "starting", not "unhealthy".
HEALTHCHECK --interval=30s --timeout=5s --start-period=330s --retries=3 \
    CMD grep -q decree /proc/1/comm || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
