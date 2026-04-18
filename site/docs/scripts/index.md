---
sidebar_position: 1
---

# Scripts

Full reference for `existential.sh` and the `src/` script library.

## `existential.sh`

```bash
./existential.sh                  # Process .example files + generate docker-compose.yml
./existential.sh --force          # Overwrite existing files too
./existential.sh examples         # Process .example files only
./existential.sh compose [file]   # Regenerate docker-compose.yml
./existential.sh setup <name>     # Configure an integration: gmail, rclone
./existential.sh test [name]      # Run tests: all (default), syntax, gmail, rclone
```

## Placeholder System

| Placeholder | Description |
|---|---|
| `EXIST_CLI` | Prompts user for input during setup |
| `EXIST_24_CHAR_PASSWORD` | Generates a secure 24-character password |
| `EXIST_32_CHAR_HEX_KEY` | Generates a 32-character hex key |
| `EXIST_64_CHAR_HEX_KEY` | Generates a 64-character hex key |
| `EXIST_TIMESTAMP` | Current timestamp (`YYYYMMDD_HHMMSS`) |
| `EXIST_UUID` | UUID |
| `EXIST_DEFAULT_*` | Propagates matching variable from root `.env.exist` |

## Docker Network

All services connect to a shared `exist` bridge network. Services communicate using container names as hostnames (e.g., `librechat-api` can reach `librechat-mongodb:27017`).

## Post-Startup Setup

After containers are running, some services need additional initialization:

```bash
./src/run_initial_setup.sh           # Run all service setup scripts
./src/run_initial_setup.sh vikunja   # Vikunja only
./src/run_initial_setup.sh info      # Show service URLs and credentials
```

## `src/generate-compose.py`

The compose merger — runs inside `existential-adhoc` via `./existential.sh compose`. Uses `python3-yaml` (standard Debian package, already in the decree image) to:

1. Read `EXIST_ENABLE_*=true` from `.env.exist`
2. Discover matching `docker-compose.yml` files at depth 2 (generated from `.docker-compose.yml.example` counterparts by `existential.sh`)
3. Adjust all relative volume/build/env_file paths to be correct from the repo root
4. Deep-merge `services`, `volumes`, and `networks` sections
5. Archive the previous `docker-compose.yml` as `docker-compose-<timestamp_ms>.yml`
6. Write the unified `docker-compose.yml`
7. Generate a master `.env` by merging `.env.exist` with all enabled service `.env` files — Docker Compose auto-loads this for variable substitution

## Script Reference

### `create_vikunja_user.sh`

Creates the default admin user in Vikunja after containers start. Waits for the database and service to be ready before attempting creation.

Environment variables: `VIKUNJA_DEFAULT_USERNAME`, `VIKUNJA_DEFAULT_PASSWORD`, `VIKUNJA_DEFAULT_EMAIL`, `VIKUNJA_DATABASE_*`

### `generate_password.sh` / `generate_hex_key.sh`

Utility scripts for generating credentials. Used internally by the placeholder system.

```bash
source src/generate_password.sh
password=$(generate_24_char_password)

source src/generate_hex_key.sh
key=$(generate_32_char_hex)
```
