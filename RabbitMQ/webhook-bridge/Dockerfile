FROM denoland/deno:alpine

WORKDIR /app

# Copy the Deno script
COPY main.ts .
COPY deps.ts .

# Cache the dependencies (including npm modules)
RUN deno cache --reload --node-modules-dir deps.ts

# Set Tini as subreaper to handle zombie processes
ENV TINI_SUBREAPER=true

# Run with permissions for network, environment variables, and npm packages
CMD ["deno", "run", "--allow-net", "--allow-env", "main.ts"]
