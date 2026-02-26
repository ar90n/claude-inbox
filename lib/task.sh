#!/bin/bash
# lib/task.sh: Atomic task operations (infrastructure layer)
#
# Sourced by worker and preprocessor. These are system-level functions,
# not skills — agents never invoke them directly.
#
# Tasks are directories: tasks/{job_id}/ containing prompt.txt, optional meta, optional files.
# Atomicity: All operations use the write-to-tmp + mv(2) rename pattern.

: "${CLAUDE_INBOX:?CLAUDE_INBOX is not set}"

# --- claim: Pick one task directory from tasks/ and move it to cur/$WORKER_ID/ ---
# Success: prints directory path to stdout, returns 0
# No task or lost race: returns 1
task_claim() {
    local worker_id="${1:?worker_id required}"
    local cur_dir="$CLAUDE_INBOX/cur/$worker_id"
    mkdir -p "$cur_dir"

    local max_retry=3
    for (( i=0; i<max_retry; i++ )); do
        local task_dir
        task_dir=$(find "$CLAUDE_INBOX/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
                   | sort | head -1)
        [ -z "$task_dir" ] && return 1

        local job_id
        job_id=$(basename "$task_dir")

        if mv "$task_dir" "$cur_dir/$job_id" 2>/dev/null; then
            echo "$cur_dir/$job_id"
            return 0
        fi
    done
    return 1
}

# --- complete: Write result and move task directory to done/ ---
task_complete() {
    local task_dir="${1:?task_dir required}"
    local result="${2:-}"

    [ -d "$task_dir" ] || { echo "ERROR: $task_dir not found" >&2; return 2; }

    local job_id
    job_id=$(basename "$task_dir")

    mkdir -p "$CLAUDE_INBOX/done"
    printf '%s\n' "$result" > "$task_dir/result"
    mv "$task_dir" "$CLAUDE_INBOX/done/$job_id"
}

# --- fail: Write error and move task directory to failed/ ---
task_fail() {
    local task_dir="${1:?task_dir required}"
    local error="${2:-}"

    [ -d "$task_dir" ] || { echo "ERROR: $task_dir not found" >&2; return 2; }

    local job_id
    job_id=$(basename "$task_dir")

    mkdir -p "$CLAUDE_INBOX/failed"
    printf '%s\n' "$error" > "$task_dir/result"
    mv "$task_dir" "$CLAUDE_INBOX/failed/$job_id"
}

# --- submit: Create a new .task file in new/ (for bridge/CLI) ---
# The preprocessor converts these into task directories.
# Prints the file path to stdout.
task_submit() {
    local prompt=""
    local priority=5

    while [ $# -gt 0 ]; do
        case "$1" in
            --prompt)   prompt="$2";   shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done

    [ -z "$prompt" ] && prompt=$(cat)
    [ -z "$prompt" ] && { echo "ERROR: no prompt" >&2; return 2; }

    local ts rand task_id
    ts=$(date +%Y%m%d-%H%M%S)
    rand=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    task_id="${priority}.${ts}.${rand}"

    mkdir -p "$CLAUDE_INBOX"/{tmp,new}

    local tmp_file="$CLAUDE_INBOX/tmp/$task_id.task"
    printf '%s\n' "$prompt" > "$tmp_file"

    mv "$tmp_file" "$CLAUDE_INBOX/new/$task_id.task"
    echo "$CLAUDE_INBOX/new/$task_id.task"
}

# --- recover: Move orphaned task directories from cur/$WORKER_ID/ back to tasks/ ---
task_recover() {
    local worker_id="${1:?worker_id required}"
    local cur_dir="$CLAUDE_INBOX/cur/$worker_id"

    local d
    for d in "$cur_dir"/*/; do
        [ -d "$d" ] || continue
        mv "$d" "$CLAUDE_INBOX/tasks/" 2>/dev/null || true
    done
    rmdir "$cur_dir" 2>/dev/null || true
}

# --- Session locking ---
# Prevent concurrent access to the same Claude session.
# Uses flock: kernel-managed, auto-released on process death (including SIGKILL).
# Non-blocking: returns 1 if session is busy (caller should re-queue).
SESSION_LOCK_FD=""

session_lock() {
    local session_id="$1"
    [ -z "$session_id" ] && return 0

    local lock_dir="$CLAUDE_INBOX/state/session"
    mkdir -p "$lock_dir"

    # Open lock file on a dynamic fd
    exec {SESSION_LOCK_FD}>"$lock_dir/${session_id}.flock"

    # Non-blocking: try to acquire, fail fast if held by another worker
    if flock -n "$SESSION_LOCK_FD"; then
        return 0
    fi

    # Lock held — close fd, report busy
    exec {SESSION_LOCK_FD}>&-
    SESSION_LOCK_FD=""
    return 1
}

session_unlock() {
    if [ -n "${SESSION_LOCK_FD:-}" ]; then
        exec {SESSION_LOCK_FD}>&-
        SESSION_LOCK_FD=""
    fi
}
