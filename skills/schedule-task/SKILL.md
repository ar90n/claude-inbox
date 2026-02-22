---
name: schedule-task
description: >
  This skill should be used when the user asks to "schedule a task",
  "set up a cron job", "run something every day/hour/week",
  "create a recurring task", or needs periodic automated task execution.
---

# Schedule Task (Cron)

Register a recurring task that executes on a cron schedule.

## How It Works

Create a `.job` file in `$CLAUDE_INBOX/schedule/cron.d/`. The `claude-inbox-cron`
daemon checks these files every 30 seconds and submits matching tasks.

## Creating a Job

```bash
# Extract chat_id from current task metadata for Telegram replies
chat_id=$(head -1 /dev/stdin <<< "$TASK_CONTENT" | grep -oP 'chat_id=\K[^ \]]*')

cat > "$CLAUDE_INBOX/schedule/cron.d/my-job-name.job" <<EOF
name=my-job-name
schedule=0 8 * * *
prompt=Your task prompt here
channel=telegram
chat_id=$chat_id
EOF
```

## Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique job name (also determines session continuity) |
| `schedule` | yes | 5-field cron: `min hour dom month dow` |
| `prompt` | yes | The task prompt |
| `channel` | no | Set to `telegram` to get replies in Telegram |
| `chat_id` | no | Telegram chat ID (required if channel=telegram) |
| `priority` | no | 0-9, default 5 |
| `model` | no | Model override (haiku/sonnet/opus) |

## Schedule Syntax

Standard 5-field cron format:
- `*` = every
- `*/5` = every 5 (step)
- `1,3,5` = specific values
- `1-5` = range
- Day of week: 1=Mon ... 7=Sun

Examples:
- `0 8 * * *` = every day at 8:00 AM
- `0 8 * * 1` = every Monday at 8:00 AM
- `*/30 * * * *` = every 30 minutes
- `0 9,18 * * 1-5` = 9 AM and 6 PM on weekdays

## Session Continuity

Each job gets a deterministic session_id (`uuid5("cron:{name}")`).
Repeated runs of the same job share a Claude session, so the agent
can reference previous executions.

## Managing Jobs

```bash
# List all jobs
ls "$CLAUDE_INBOX/schedule/cron.d/"

# View a job
cat "$CLAUDE_INBOX/schedule/cron.d/my-job-name.job"

# Remove a job
rm "$CLAUDE_INBOX/schedule/cron.d/my-job-name.job"
```

## Deriving chat_id

When registering a job from a Telegram task, extract `chat_id` from
the current task's metadata header:

```bash
# The metadata is on the first line of the task content
# Example: [from=User channel=telegram chat_id=12345 msg_id=200 session_id=xxx]
```

The `chat_id` should be included in the job so the cron-triggered
task can reply to the user's Telegram chat.
