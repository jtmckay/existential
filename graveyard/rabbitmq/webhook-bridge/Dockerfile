FROM denoland/deno:latest

WORKDIR /app

# Copy dependency files
COPY deps.ts .
COPY main.ts .

# Cache dependencies
RUN deno cache deps.ts

# Run the application with necessary permissions
CMD ["deno", "run", "--allow-net", "--allow-read", "main.ts"]
