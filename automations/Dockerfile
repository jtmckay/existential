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
COPY package.json /opt/decree/package.json
RUN cd /opt/decree && npm install --no-fund --no-audit
ENV NODE_PATH=/opt/decree/node_modules
ENV PATH=/opt/decree/node_modules/.bin:$PATH
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
