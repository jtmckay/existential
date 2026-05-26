FROM rust:slim-bookworm AS builder
RUN cargo install decree --version 0.4.1

FROM debian:bookworm-slim
COPY --from=builder /usr/local/cargo/bin/decree /usr/local/bin/decree
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        poppler-utils python3 python3-yaml curl jq dnsutils \
        postgresql-client default-mysql-client gnupg ca-certificates \
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
    && chmod +x /usr/local/bin/yq
