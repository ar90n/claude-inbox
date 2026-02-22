---
name: url-watch
description: >
  This skill should be used when the user asks to "watch a URL",
  "monitor a webpage", "notify me when something changes", "track
  releases", "watch for updates", or needs to detect changes on a
  web page or API endpoint.
---

# URL Watch

Monitor a URL for content changes and get notified.

## How It Works

Create a `.watch` file in `$CLAUDE_INBOX/schedule/watch.d/`. The
`claude-inbox-url-watch` daemon polls URLs at specified intervals,
detects changes via content hashing, and submits tasks with diff
context when changes are detected.

## Creating a Watch

```bash
# Extract chat_id from current task metadata for Telegram replies
chat_id=$(head -1 /dev/stdin <<< "$TASK_CONTENT" | grep -oP 'chat_id=\K[^ \]]*')

cat > "$CLAUDE_INBOX/schedule/watch.d/my-watch.watch" <<EOF
name=my-watch
url=https://example.com/api/endpoint
interval=3600
prompt=The monitored page has changed. Summarize the changes and notify me.
channel=telegram
chat_id=$chat_id
EOF
```

## Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique watch name |
| `url` | yes | URL to poll |
| `interval` | yes | Check interval in seconds (3600 = hourly) |
| `prompt` | yes | Task prompt (change details are appended automatically) |
| `channel` | no | Set to `telegram` for Telegram replies |
| `chat_id` | no | Telegram chat ID (required if channel=telegram) |
| `content_filter` | no | Shell command to filter response before hashing |
| `headers` | no | HTTP headers (e.g., `Authorization: token xxx`) |
| `priority` | no | 0-9, default 5 |
| `model` | no | Model override |

## Content Filter

Use `content_filter` to track only specific parts of a response:

```
# Track only the latest release tag name
content_filter=jq -r '.tag_name'

# Track only the page title
content_filter=grep -oP '<title>\K[^<]+'
```

If the filter command fails, the raw content is used as fallback.

## Interval Guidelines

| Use case | Interval |
|----------|----------|
| GitHub releases | 3600 (hourly) |
| Blog RSS feeds | 1800 (30 min) |
| Price monitoring | 300 (5 min) |
| Status page | 60 (1 min) |

## What Happens on Change

When a change is detected, a task is submitted with:
- Your prompt
- A diff between old and new content
- The current content (truncated to 200 lines)

The agent processes this task and can summarize changes,
send notifications, or take other actions.

## Managing Watches

```bash
# List all watches
ls "$CLAUDE_INBOX/schedule/watch.d/"

# View a watch
cat "$CLAUDE_INBOX/schedule/watch.d/my-watch.watch"

# Remove a watch
rm "$CLAUDE_INBOX/schedule/watch.d/my-watch.watch"
```
