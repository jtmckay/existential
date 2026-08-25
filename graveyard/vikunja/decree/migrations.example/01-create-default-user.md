---
routine: develop
---
Create the default Vikunja user via the HTTP API using credentials from
VIKUNJA_DEFAULT_USERNAME, VIKUNJA_DEFAULT_PASSWORD, and VIKUNJA_DEFAULT_EMAIL.

Run the following shell commands (no AI required — use bash):

```bash
username="${VIKUNJA_DEFAULT_USERNAME:-admin}"
password="${VIKUNJA_DEFAULT_PASSWORD}"
email="${VIKUNJA_DEFAULT_EMAIL:-admin@localhost}"
vikunja_url="http://vikunja:3456"

if [ -z "$password" ]; then
  echo "VIKUNJA_DEFAULT_PASSWORD is not set — skipping user creation."
  exit 0
fi

# Check if user already exists by attempting login
existing=$(curl -sf -X POST "${vikunja_url}/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${username}\",\"password\":\"${password}\"}" 2>/dev/null \
  | grep -c '"token"' || true)

if [ "$existing" -gt 0 ]; then
  echo "User '${username}' already exists and credentials are valid — nothing to do."
  exit 0
fi

# Register the user
response=$(curl -sf -X POST "${vikunja_url}/api/v1/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${username}\",\"password\":\"${password}\",\"email\":\"${email}\"}" 2>&1)

if echo "$response" | grep -q '"id"'; then
  echo "Created user '${username}' (${email})."
  echo "Login at https://vikunja.internal"
else
  echo "User creation response: ${response}"
  # Registration may be disabled after first user — not an error
  echo "If registration is disabled, user may already exist. Verify by logging in."
fi
```
