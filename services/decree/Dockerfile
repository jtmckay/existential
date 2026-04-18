FROM ghcr.io/jtmckay/decree:latest
RUN apt-get update \
    && apt-get install -y --no-install-recommends poppler-utils python3 python3-yaml curl jq \
    && curl -fsSL https://downloads.rclone.org/rclone-current-linux-amd64.deb -o /tmp/rclone.deb \
    && dpkg -i /tmp/rclone.deb \
    && rm /tmp/rclone.deb \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*
