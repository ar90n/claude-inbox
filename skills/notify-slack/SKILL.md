---
name: notify-slack
description: >
  This skill should be used when the agent needs to "send a message on
  Slack", "notify via Slack", or "post to Slack channel".
  Uses Slack Incoming Webhook. Requires SLACK_WEBHOOK_URL.
---

# Slack Notification

Send messages to a Slack channel via Incoming Webhook.

## Environment Variables

- `SLACK_WEBHOOK_URL`: Incoming Webhook URL (required)

## Sending Messages

```bash
curl -sf -X POST "$SLACK_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"text\": \"$MESSAGE\"}"
```

## Formatting

Use Slack mrkdwn format:
- `*bold*`, `_italic_`, `~strikethrough~`
- `` `code` ``, ` ```code block``` `
- `<url|text>` for links

## Error Handling

- Network error: retry once after 5s.
- 2 failures: report error, do not retry.
