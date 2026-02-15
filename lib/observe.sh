#!/bin/bash
# lib/observe.sh: System monitoring notifications (deterministic, agent-independent)
#
# Separated from the agent reply channel. Used for operational logging:
# worker deaths, start/stop events, auth expiry detection, etc.
#
# Environment variables:
#   OBSERVE_TELEGRAM_BOT_TOKEN  Monitoring bot token (can differ from the reply bot)
#   OBSERVE_TELEGRAM_CHAT_ID    Monitoring chat ID (can differ from the reply chat)
#
# Agent replies:      handled by skills/notify-telegram/ (agent decides)
# System monitoring:  handled by this lib/observe.sh (bash runs deterministically)

observe() {
    local message="$1"
    local token="${OBSERVE_TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${OBSERVE_TELEGRAM_CHAT_ID:-}"

    # Fall back to stderr if not configured
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        echo "[observe] $message" >&2
        return 0
    fi

    # Send deterministically; never kill the process on failure
    curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat "$chat_id" \
            --arg text "[claude-inbox] $message" \
            '{chat_id: $chat, text: $text}')" \
        >/dev/null 2>&1 || true
}
