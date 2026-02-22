#!/bin/bash
# lib/notify.sh: Direct Telegram message sending (deterministic, agent-independent)
#
# Sends messages via TELEGRAM_BOT_TOKEN to a specific chat_id.
# Used by worker (progress notification) and future daemons.
#
# Unlike lib/observe.sh (system monitoring channel using OBSERVE_TELEGRAM_*),
# this sends to the user's chat via the same bot token the agent uses.

# notify_telegram(chat_id, text, [reply_to_message_id])
# Sends a message to the specified chat. Fails silently (|| true).
notify_telegram() {
    local chat_id="$1"
    local text="$2"
    local reply_to="${3:-}"
    local token="${TELEGRAM_BOT_TOKEN:-}"

    [ -z "$token" ] || [ -z "$chat_id" ] && return 0

    local reply_json=""
    [ -n "$reply_to" ] && reply_json="\"reply_to_message_id\": $reply_to,"

    curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat "$chat_id" \
            --arg text "$text" \
            "{chat_id: \$chat, ${reply_json} text: \$text}")" \
        >/dev/null 2>&1 || true
}
