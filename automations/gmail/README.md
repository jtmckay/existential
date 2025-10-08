# Gmail Authentication

Simple Gmail API authentication that saves a token for other scripts to use.

## Setup & Run

1. **Setup:**

   ```bash
   make setup
   ```

2. **Get Gmail API credentials:**

   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Enable Gmail API
   - Create OAuth 2.0 credentials
   - Download as `credentials.json` and place it in this directory (`/automations/gmail/`)

3. **Authenticate:**
   ```bash
   make run
   ```

This creates `token.json` that other scripts can use for Gmail API access.

Note: `make clean` will clear out the `make setup` changes
