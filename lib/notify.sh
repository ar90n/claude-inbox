#!/bin/bash
# lib/notify.sh: Telegram message sending (shared by notify + observe)
#
# Two channels, one mechanism:
#   notify_telegram()  — agent reply channel (TELEGRAM_BOT_TOKEN)
#   observe()          — system monitoring channel (OBSERVE_TELEGRAM_*)

# _send_telegram(token, chat_id, text, [reply_to_message_id])
# Low-level Telegram sendMessage. Fails silently (|| true).
_send_telegram() {
    local token="$1" chat_id="$2" text="$3" reply_to="${4:-}"

    [ -z "$token" ] || [ -z "$chat_id" ] && return 0

    local payload
    if [ -n "$reply_to" ]; then
        payload=$(jq -n \
            --arg chat "$chat_id" \
            --arg text "$text" \
            --argjson reply "$reply_to" \
            '{chat_id: $chat, text: $text, reply_to_message_id: $reply}')
    else
        payload=$(jq -n \
            --arg chat "$chat_id" \
            --arg text "$text" \
            '{chat_id: $chat, text: $text}')
    fi

    curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        >/dev/null 2>&1 || true
}

# notify_telegram(chat_id, text, [reply_to_message_id])
# Sends a message to the user's chat via the agent bot token.
notify_telegram() {
    _send_telegram "${TELEGRAM_BOT_TOKEN:-}" "$1" "$2" "${3:-}"
}
