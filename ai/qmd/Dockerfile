# qmd: hybrid (BM25 + neural) search over the workspace's Markdown, served as MCP.
# Upstream: https://github.com/tobi/qmd (MIT), installed from npm at a pinned version.
# pdftotext (poppler) and mammoth turn PDF and Word files into Markdown for it:
# text layers only, no OCR.
FROM node:24.22.1-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends poppler-utils \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @tobilu/qmd@2.8.3 mammoth@1.12.3 && npm cache clean --force
# Index, config and models all live in the /cache volume, for the server and
# for `docker exec qmd qmd status` alike.
ENV HOME=/cache XDG_CACHE_HOME=/cache XDG_CONFIG_HOME=/cache/config
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
