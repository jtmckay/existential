#!/usr/bin/env bash
# Shared helpers for the comfy machine's script (automation/scripts/comfy.sh).
# Sourced, never run directly.

# Strip YAML frontmatter (--- delimited) and leading blank lines.
# If no frontmatter is present, returns the entire file.
comfy_read_body() {
    local has_fm
    has_fm=$(head -1 "$1")
    if [ "$has_fm" = "---" ]; then
        awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$1" | sed '/\S/,$!d'
    else
        sed '/\S/,$!d' "$1"
    fi
}

# POST $1=payload to $2=api_url, logging payload/response under $3=run_dir
# (if set). Prints the response body and sets COMFY_HTTP_CODE.
comfy_submit() {
    local payload="$1" api_url="$2" run_dir="$3"

    if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
        echo "$payload" > "${run_dir}/comfy-payload.json"
        echo "  Payload:  ${run_dir}/comfy-payload.json"
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
      -H 'Content-Type: application/json' \
      --data-raw "$payload")

    COMFY_HTTP_CODE=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    echo "=== Response (HTTP $COMFY_HTTP_CODE) ==="
    echo "$body"

    if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
        echo "$body" > "${run_dir}/comfy-response.json"
    fi
}
