#!/bin/bash

# Lucid Memory - Stop Hook (Claude Code)
#
# This hook runs after Claude responds. It captures the assistant's response
# and stores it as a "learning" memory for future context retrieval.
#
# The hook receives a JSON payload on stdin with:
#   - last_assistant_message: the assistant's response text
#   - cwd: current working directory
#   - hook_event_name: "Stop"
#
# Installation:
#   Handled by install.sh — registers in ~/.claude/settings.json
#
# Environment:
#   LUCID_BIN - Path to lucid CLI (default: ~/.lucid/bin/lucid)
#   LUCID_DEBUG - Set to 1 to enable debug logging

LOG_FILE="${HOME}/.lucid/logs/hook.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

log_debug() {
    if [ "${LUCID_DEBUG:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [stop] $1" >> "$LOG_FILE"
    fi
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [stop] ERROR: $1" >> "$LOG_FILE"
}

# Read JSON payload from stdin
PAYLOAD=$(cat)

if [ -z "$PAYLOAD" ]; then
    log_debug "No payload received"
    exit 0
fi

LUCID="${LUCID_BIN:-$HOME/.lucid/bin/lucid}"

if [ ! -x "$LUCID" ]; then
    log_error "Lucid CLI not found at $LUCID"
    exit 0
fi

# Extract last_assistant_message — try jq, then python3, then raw fallback
extract_field() {
    local field="$1"

    if command -v jq &> /dev/null; then
        echo "$PAYLOAD" | jq -r ".$field // empty" 2>/dev/null
        return
    fi

    if command -v python3 &> /dev/null; then
        echo "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('$field',''); print(v if v else '')" 2>/dev/null
        return
    fi

    # Raw fallback: grep for the field (works for simple flat JSON)
    echo "$PAYLOAD" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*":\s*"//;s/"$//'
}

RESPONSE=$(extract_field "last_assistant_message")
PROJECT_PATH=$(extract_field "cwd")
PROJECT_PATH="${PROJECT_PATH:-$(pwd)}"

# Skip empty or trivial responses
if [ -z "$RESPONSE" ]; then
    log_debug "No assistant message in payload"
    exit 0
fi

if [ ${#RESPONSE} -lt 20 ]; then
    log_debug "Response too short (${#RESPONSE} chars), skipping"
    exit 0
fi

WORD_COUNT=$(echo "$RESPONSE" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -lt 10 ]; then
    log_debug "Response too few words ($WORD_COUNT), skipping"
    exit 0
fi

# Truncate to 2000 chars
if [ ${#RESPONSE} -gt 2000 ]; then
    RESPONSE="${RESPONSE:0:2000}"
    log_debug "Truncated response to 2000 chars"
fi

log_debug "Storing assistant response ($WORD_COUNT words, ${#RESPONSE} chars) for project: $PROJECT_PATH"

(
    if ! "$LUCID" store "$RESPONSE" --type=learning --project="$PROJECT_PATH" 2>> "$LOG_FILE"; then
        log_error "Failed to store assistant response"
    fi
) &

exit 0
