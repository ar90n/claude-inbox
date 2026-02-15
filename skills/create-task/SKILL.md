---
name: create-task
description: >
  This skill should be used when the agent needs to "submit a follow-up
  task", "queue a new task", "chain another step", or when the current
  task's result should trigger additional processing.
---

# Create Task

Submit a new task to the inbox queue.

## Session Continuity

When creating a follow-up task that should share context with the
current session, include `session_id` in the metadata so the next
worker can `--resume` and retain full conversation context:

```bash
source "$CLAUDE_INBOX/lib/task.sh"

# With session continuity (preferred for chained tasks)
# The session_id is available from the current task's metadata
task_submit --prompt "[session_id=$CURRENT_SESSION_ID]
Generate a podcast from the news we just collected"

# Without session (independent task)
task_submit --prompt "Check if nlm authentication is still valid"
```

## Priority

```bash
task_submit --priority 1 --prompt "Urgent: ..."  # 0=highest, 9=lowest, default=5
```

## Guidelines

- If passing `session_id`, the next agent inherits full context via
  `--resume` — no need to repeat results inline.
- If not passing `session_id`, write a self-contained prompt with
  all necessary information.
- The worker automatically tries `--resume` first and falls back to
  `--session-id` if the session doesn't exist yet.
