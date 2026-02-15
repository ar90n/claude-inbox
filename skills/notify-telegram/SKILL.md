---
name: notify-telegram
description: >
  This skill should be used when the agent needs to "send a message on
  Telegram", "notify me", "share results via Telegram", "reply to the
  user on Telegram". Uses the Telegram Bot API.
  Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID.
---

# Telegram Notification

Send messages to a Telegram chat via Bot API.

## Environment Variables

- `TELEGRAM_BOT_TOKEN`: Bot token from BotFather (required)
- `TELEGRAM_CHAT_ID`: Default target chat (overridden by task metadata)

## Sending Messages

Extract `chat_id` from the task metadata. Optionally use `msg_id` for
`reply_to_message_id` to improve UX (the reply appears linked to the
user's original message in the chat).

```bash
# Extract from task metadata (first line of the task content)
chat_id=$(head -1 "$TASK_FILE" | grep -oP 'chat_id=\K[^ \]]*')
msg_id=$(head -1 "$TASK_FILE" | grep -oP 'msg_id=\K[^ \]]*')

# Use chat_id from metadata, fall back to env var
chat_id="${chat_id:-$TELEGRAM_CHAT_ID}"

# Build request — reply_to_message_id is optional (UX improvement)
reply_args=""
[ -n "$msg_id" ] && reply_args='"reply_to_message_id": '$msg_id','

curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"$chat_id\",
    $reply_args
    \"text\": \"$MESSAGE\",
    \"parse_mode\": \"Markdown\"
  }"
```

## Message Limits

Telegram caps at 4096 chars. For longer content:
1. Split at ~4000 chars on paragraph boundaries
2. Send sequentially with 0.5s sleep between chunks
3. Only the **first** chunk needs `reply_to_message_id`

## Markdown (v1)

Safe subset: `*bold*`, `_italic_`, `` `code` ``, ` ```pre``` `, `[text](url)`.
Avoid MarkdownV2.

## Error Handling

- HTTP 429: wait `retry_after` seconds, retry once.
- HTTP 400: retry without parse_mode.
- Network error: retry once after 5s.
- 2 failures: report error, do not retry.
