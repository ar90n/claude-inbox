---
name: manage-inbox
description: >
  This skill should be used when the user asks to "show task status",
  "list pending/failed tasks", "cancel a task", "retry a failed task",
  "list cron jobs", "remove a cron job", "list watched URLs",
  "remove a watch", or needs to inspect or manage the inbox queue.
---

# Manage Inbox

Inspect and manage the task queue, cron jobs, and URL watches.

All paths are relative to `$CLAUDE_INBOX`.

## Task Queue

Tasks are directories containing `prompt.txt`, optional `meta`, optional attached files, and `result` (after completion).

### List tasks

```bash
# Pending (preprocessed, waiting for a worker)
ls "$CLAUDE_INBOX/tasks/"

# In preprocessing (inbox items not yet converted to tasks)
ls "$CLAUDE_INBOX/new/"

# In progress (per-worker)
ls "$CLAUDE_INBOX/cur/"*/

# Recently completed (newest first)
ls -t "$CLAUDE_INBOX/done/" 2>/dev/null | head -20

# Failed
ls "$CLAUDE_INBOX/failed/" 2>/dev/null
```

### Inspect a task

```bash
# Task prompt
cat "$CLAUDE_INBOX/done/$JOB_ID/prompt.txt"

# Task metadata
cat "$CLAUDE_INBOX/done/$JOB_ID/meta"

# Task result
cat "$CLAUDE_INBOX/done/$JOB_ID/result"

# Failed task error
cat "$CLAUDE_INBOX/failed/$JOB_ID/result"

# List attached files
ls "$CLAUDE_INBOX/done/$JOB_ID/"
```

Job ID format: `YYYYMMDD-HHMMSS.random_hex` (e.g. `20260226-083000.a1b2c3d4`).

### Cancel a pending task

```bash
rm -rf "$CLAUDE_INBOX/tasks/$JOB_ID"
```

Only tasks in `tasks/` can be cancelled. Tasks in `cur/` are being processed
by a worker and cannot be interrupted.

### Retry a failed task

```bash
mv "$CLAUDE_INBOX/failed/$JOB_ID" "$CLAUDE_INBOX/tasks/"
```

The task re-enters the queue for the next available worker.

## Cron Jobs

```bash
# List all jobs
ls "$CLAUDE_INBOX/schedule/cron.d/"

# View a job
cat "$CLAUDE_INBOX/schedule/cron.d/$NAME.job"

# Remove a job
rm "$CLAUDE_INBOX/schedule/cron.d/$NAME.job"
```

## URL Watches

```bash
# List all watches
ls "$CLAUDE_INBOX/schedule/watch.d/"

# View a watch
cat "$CLAUDE_INBOX/schedule/watch.d/$NAME.watch"

# Remove a watch
rm "$CLAUDE_INBOX/schedule/watch.d/$NAME.watch"
```

## Notes

- Summarize results rather than dumping raw output (results can be long).
- If a listing is empty, report "none".
