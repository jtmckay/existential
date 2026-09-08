#!/usr/bin/env bash
# Shared helpers for the comfy routine's subroutines (see
# ../../shared_routines/comfy.sh). Sourced, never run directly.

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

# Read prompt text from $1=spec_file (preferred) or $2=message_file.
comfy_prompt_text() {
    local spec_file="$1" message_file="$2"
    if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
        comfy_read_body "$spec_file"
    elif [ -n "$message_file" ] && [ -f "$message_file" ]; then
        comfy_read_body "$message_file"
    else
        echo "Error: No spec or message file provided" >&2
        return 1
    fi
}

# POST $1=payload to $2=api_url, logging payload/response under $3=message_dir
# (if set). Prints the response body and sets COMFY_HTTP_CODE.
comfy_submit() {
    local payload="$1" api_url="$2" message_dir="$3"

    if [ -n "$message_dir" ] && [ -d "$message_dir" ]; then
        echo "$payload" > "${message_dir}/comfy-payload.json"
        echo "  Payload:  ${message_dir}/comfy-payload.json"
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

    if [ -n "$message_dir" ] && [ -d "$message_dir" ]; then
        echo "$body" > "${message_dir}/comfy-response.json"
    fi
}
