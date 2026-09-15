FROM rust:slim-bookworm AS builder
# --locked: build against the versions decree's own Cargo.lock pins. Without it
# `cargo install` re-resolves every transitive dependency at build time, so the
# same --version can produce a different binary on two different days.
RUN cargo install decree --version 0.4.2 --locked

FROM debian:bookworm-slim
# Third-party binaries installed as root. Each is pinned to a version AND
# verified against a checksum recorded here, because a version alone only says
# what we asked for, not what we got. Bumping any of these means bumping its
# checksum in the same commit — get it from the vendor:
#   rclone  https://github.com/rclone/rclone/releases/download/v<V>/SHA256SUMS
#   yq      https://github.com/mikefarah/yq/releases/download/v<V>/checksums
#   node    https://nodejs.org/dist/v<V>/SHASUMS256.txt
#
# ARG, not ENV, and that is load-bearing: rclone reads every RCLONE_* variable in
# its environment as a flag override, so a persisted `RCLONE_VERSION=1.75.1`
# lands on its boolean --version flag and every rclone call in the container
# dies with "invalid argument for --version". ARG is build-scope only, so
# nothing leaks into the running container. None of these is needed at runtime.
ARG NODE_VERSION=24.16.0
ARG NODE_SHA256=d804845d34eddc21dc1092b519d643ef40b1f58ec5dec5c22b1f4bd8fabde6c9
ARG RCLONE_VERSION=1.75.1
ARG RCLONE_SHA256=09c9f7606ed9e31eecc1eec26a89992cf2931a8d2d1a5f0ae2bb1c11630ffb15
ARG YQ_VERSION=4.44.3
ARG YQ_SHA256=a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7
COPY --from=builder /usr/local/cargo/bin/decree /usr/local/bin/decree
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        poppler-utils curl jq dnsutils xz-utils fzf rsync openssh-client \
        postgresql-client default-mysql-client sqlite3 gnupg ca-certificates \
        git python3 \
    && curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.deb" \
        -o /tmp/rclone.deb \
    && echo "${RCLONE_SHA256}  /tmp/rclone.deb" | sha256sum -c - \
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
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /usr/local/bin/yq \
    && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - \
    && chmod +x /usr/local/bin/yq \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && npm install -g npm@11.16.0 \
    && rm -rf /var/lib/apt/lists/*
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml /opt/decree/
# Reproducible, integrity-checked install via pnpm (version pinned by package.json's
# packageManager field, provisioned by corepack). The committed pnpm-lock.yaml pins the
# full tree; --frozen-lockfile fails the build if package.json drifts from it. pnpm runs
# NO dependency build scripts except the allowlist in pnpm-workspace.yaml's
# `allowBuilds` (better-sqlite3, esbuild) — pnpm 11 reads that setting there, not
# from a "pnpm" field in package.json. Closes the install-script supply-chain
# hole that `npm install` left open. node-linker=hoisted (.npmrc) keeps the
# flat node_modules layout that NODE_PATH below relies on.
RUN cd /opt/decree \
    && corepack enable \
    && pnpm install --frozen-lockfile --prod
ENV NODE_PATH=/opt/decree/node_modules
ENV PATH=/opt/decree/node_modules/.bin:$PATH
# code-server's entrypoint installs the claude CLI at runtime via `npm i -g`
# (the decree daemons install nothing — they reach hermes over HTTP). That
# container runs as the dynamic host user (EXIST_PUID — any
# uid), but the image's default HOME (/root) and global prefix (/usr/local) are
# root-owned, so npm's cache and install both fail with EACCES. Point HOME, the
# npm cache, and the npm global prefix at a world-writable dir (0777, since the
# uid:gid is not known at build time) and put its bin on PATH. Placed after the
# build's root-run npm/pnpm steps so only the runtime install uses these paths.
ENV HOME=/home/decree \
    NPM_CONFIG_CACHE=/home/decree/.npm \
    NPM_CONFIG_PREFIX=/home/decree/.npm-global
ENV PATH=/home/decree/.npm-global/bin:$PATH
RUN mkdir -p /home/decree/.npm /home/decree/.npm-global \
    && chmod -R 0777 /home/decree
# /etc/passwd has no entry for EXIST_PUID (unknown at build time, same reason
# as the 0777 above) — OpenSSH's getpwuid() lookup hard-refuses to run at all
# without one ("No user exists for uid N"), which breaks notes-pull's
# ssh/rsync path entirely. World-writable so entrypoint.sh (already running
# as the non-root runtime uid by then, never root) can append its own line.
RUN chmod 0666 /etc/passwd
# /etc/profile unconditionally overwrites PATH for non-root login shells
# (code-server's integrated terminal launches one), dropping the npm-global
# dir set above. profile.d runs after that reset, so re-prepend it there too.
RUN printf 'PATH=/home/decree/.npm-global/bin:/opt/decree/node_modules/.bin:$PATH\nexport PATH\n' \
    > /etc/profile.d/npm-global.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# Daemon services mount their project at /work/.decree and don't set DECREE_DIR,
# so `decree daemon` must run from /work to detect the project. Without this the
# daemon dies with "not inside a decree project".
WORKDIR /work
# Liveness for the no-network decree daemons (decree and decree-backup).
# After entrypoint.sh `exec decree daemon`, PID 1's comm is "decree". A stale
# or mis-built image (no ENTRYPOINT → base CMD "bash") fails this check, and a
# dead daemon stops being PID 1 — both surface as (unhealthy) in `docker ps`.
# start-period is generous because a daemon with migrations spends up to
# DECREE_MIGRATE_TIMEOUT (default 300s) in the health-wait loop as bash first;
# during that window the check fails but stays "starting", not "unhealthy".
HEALTHCHECK --interval=30s --timeout=5s --start-period=330s --retries=3 \
    CMD grep -q decree /proc/1/comm || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
