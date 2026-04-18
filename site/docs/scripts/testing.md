---
sidebar_position: 2
---

# Testing

The test suite verifies that your integrations are working without modifying any state or posting anything. All tests are read-only.

```bash
./existential.sh test           # Run all tests
./existential.sh test syntax    # Run a single test by name
```

Tests run inside the `existential-adhoc` container. Build it once before running tests:

```bash
docker compose -f existential-compose.yml build
```

## Tests

### `syntax`

Syntax-checks every `.sh` file in `src/` using `bash -n`. This catches parse errors without executing any code.

```bash
./existential.sh test syntax
```

No setup required. Runs entirely locally.

---

### `gmail`

Verifies that saved Gmail credentials are still valid by refreshing the OAuth token and making a single read-only API call to the Gmail profile endpoint.

```bash
./existential.sh test gmail
```

**What it checks:**
- `credentials.env` exists at `services/decree/secrets/gmail/credentials.env`
- `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, and `GMAIL_REFRESH_TOKEN` are all present
- The refresh token can be exchanged for a new access token
- The access token successfully authenticates against `GET /gmail/v1/users/me/profile`

**Output on success:**
```
Gmail: connected as you@gmail.com
```

**No messages are read, sent, or modified.** The test uses the same read-only OAuth scope set up during `./existential.sh setup gmail`.

**If it fails:** Your refresh token may be expired or revoked. Re-run the setup:

```bash
./existential.sh setup gmail
```

:::note Initial setup is manual
The first time you connect Gmail, you must complete an OAuth browser flow. After that, `./existential.sh test gmail` can verify the credentials any time without re-authenticating.
:::

---

### `rclone`

Verifies that every configured rclone remote is reachable by running `rclone lsd` (list top-level directories) on each one.

```bash
./existential.sh test rclone
```

**What it checks:**
- `rclone.conf` exists at `services/decree/secrets/rclone/rclone.conf`
- At least one remote is configured
- Each remote responds to a directory listing

**Output on success:**
```
  OK: dropbox
  OK: nextcloud
rclone: all 2 remote(s) reachable
```

**No files are uploaded, downloaded, or modified.** `rclone lsd` is a metadata-only operation.

**If it fails:** The remote may be offline, credentials may be expired, or network connectivity may be down. Re-run setup for that remote:

```bash
./existential.sh setup rclone
```

:::note Initial setup is manual
Configuring a new rclone remote requires an interactive browser or device-auth flow. Once the remote is saved in `rclone.conf`, `./existential.sh test rclone` can verify connectivity any time without re-authenticating.
:::

---

## Test Philosophy

| Property | Behavior |
|---|---|
| **Read-only** | No writes, no messages sent, no files modified |
| **Non-destructive** | Safe to run at any time, on any schedule |
| **No re-authentication** | Initial setup is done once manually; tests reuse saved credentials |
| **Fast** | Each test completes in a few seconds |

The goal is a quick health check you can run after a reboot, a credential rotation, or any time you want to confirm integrations are still working.
