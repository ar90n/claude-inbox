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
#
# Increments an `attempts=N` counter in each task's meta file. Once attempts
# reach TASK_MAX_ATTEMPTS (default 3), the task is moved to failed/ instead of
# tasks/ to prevent poison-pill tasks from looping forever across worker restarts.
task_recover() {
    local worker_id="${1:?worker_id required}"
    local cur_dir="$CLAUDE_INBOX/cur/$worker_id"
    local max="${TASK_MAX_ATTEMPTS:-3}"

    local d
    for d in "$cur_dir"/*/; do
        [ -d "$d" ] || continue
        local job_id
        job_id=$(basename "$d")

        # Read existing attempts (default 0)
        local attempts=0
        if [ -f "$d/meta" ]; then
            local v
            v=$(grep -oP '^attempts=\K[0-9]+' "$d/meta" 2>/dev/null || true)
            [ -n "$v" ] && attempts="$v"
        fi
        attempts=$((attempts + 1))

        # Rewrite meta with updated attempts, preserving other fields
        local tmp_meta="$d/meta.tmp"
        if [ -f "$d/meta" ]; then
            grep -v '^attempts=' "$d/meta" > "$tmp_meta" 2>/dev/null || true
        else
            : > "$tmp_meta"
        fi
        echo "attempts=$attempts" >> "$tmp_meta"
        mv "$tmp_meta" "$d/meta"

        if [ "$attempts" -ge "$max" ]; then
            mkdir -p "$CLAUDE_INBOX/failed"
            printf 'recovered %d times (>= max %d), giving up\n' "$attempts" "$max" > "$d/result"
            mv "$d" "$CLAUDE_INBOX/failed/$job_id" 2>/dev/null || true
        else
            mv "$d" "$CLAUDE_INBOX/tasks/$job_id" 2>/dev/null || true
        fi
    done
    rm -f "$cur_dir/.heartbeat" 2>/dev/null || true
    rmdir "$cur_dir" 2>/dev/null || true
}

# --- recover_orphans: Scan cur/*/ for dead workers and recover their tasks ---
#
# A worker is presumed dead when its heartbeat file is missing or older than
# TASK_HEARTBEAT_TIMEOUT seconds (default 120). Used to clean up after a worker
# that was SIGKILL'd before its EXIT trap could run task_recover. Skips the
# current $WORKER_ID so a running worker doesn't recover itself.
task_recover_orphans() {
    local stale="${TASK_HEARTBEAT_TIMEOUT:-120}"
    local cur_root="$CLAUDE_INBOX/cur"
    [ -d "$cur_root" ] || return 0

    local now
    now=$(date +%s)

    local cur_dir
    for cur_dir in "$cur_root"/*/; do
        [ -d "$cur_dir" ] || continue
        local wid
        wid=$(basename "$cur_dir")
        [ "$wid" = "${WORKER_ID:-}" ] && continue

        local hb_file="$cur_dir/.heartbeat"
        if [ -f "$hb_file" ]; then
            local hb_ts age
            hb_ts=$(cat "$hb_file" 2>/dev/null || echo 0)
            [[ "$hb_ts" =~ ^[0-9]+$ ]] || hb_ts=0
            age=$((now - hb_ts))
            [ "$age" -lt "$stale" ] && continue
        fi

        task_recover "$wid"
    done
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
