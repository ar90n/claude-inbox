#!/bin/bash
# lib/task.sh: Atomic task operations (infrastructure layer)
#
# Sourced by worker.sh. These are system-level functions,
# not skills — agents never invoke them directly.
#
# Atomicity: All operations use the write-to-tmp + mv(2) rename pattern.

: "${CLAUDE_INBOX:?CLAUDE_INBOX is not set}"

# --- claim: Pick one task from new/ and move it to cur/$WORKER_ID/ ---
# Success: prints file path to stdout, returns 0
# No task or lost race: returns 1
task_claim() {
    local worker_id="${1:?worker_id required}"
    local cur_dir="$CLAUDE_INBOX/cur/$worker_id"
    mkdir -p "$cur_dir"

    local max_retry=3
    for (( i=0; i<max_retry; i++ )); do
        local task
        task=$(find "$CLAUDE_INBOX/new" -maxdepth 1 -name '*.task' -type f 2>/dev/null \
               | sort | head -1)
        [ -z "$task" ] && return 1

        local bname
        bname=$(basename "$task")

        if mv "$task" "$cur_dir/$bname" 2>/dev/null; then
            echo "$cur_dir/$bname"
            return 0
        fi
    done
    return 1
}

# --- complete: Write result and move task to done/ ---
task_complete() {
    local task_file="${1:?task_file required}"
    local result="${2:-}"

    [ -f "$task_file" ] || { echo "ERROR: $task_file not found" >&2; return 2; }

    local bname id
    bname=$(basename "$task_file")
    id="${bname%.task}"

    mkdir -p "$CLAUDE_INBOX"/{tmp,done}

    local rtmp="$CLAUDE_INBOX/tmp/$id.result"
    printf '%s\n' "$result" > "$rtmp"

    mv "$rtmp" "$CLAUDE_INBOX/done/$id.result"
    mv "$task_file" "$CLAUDE_INBOX/done/$bname"
}

# --- fail: Write error and move task to failed/ ---
task_fail() {
    local task_file="${1:?task_file required}"
    local error="${2:-}"

    [ -f "$task_file" ] || { echo "ERROR: $task_file not found" >&2; return 2; }

    local bname id
    bname=$(basename "$task_file")
    id="${bname%.task}"

    mkdir -p "$CLAUDE_INBOX"/{tmp,failed}

    local rtmp="$CLAUDE_INBOX/tmp/$id.result"
    printf '%s\n' "$error" > "$rtmp"

    mv "$rtmp" "$CLAUDE_INBOX/failed/$id.result"
    mv "$task_file" "$CLAUDE_INBOX/failed/$bname"
}

# --- submit: Create a new task in new/ ---
# Prints the file path to stdout
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

# --- recover: Move orphaned tasks from cur/$WORKER_ID/ back to new/ ---
task_recover() {
    local worker_id="${1:?worker_id required}"
    local cur_dir="$CLAUDE_INBOX/cur/$worker_id"

    local f
    for f in "$cur_dir"/*.task; do
        [ -f "$f" ] || continue
        mv "$f" "$CLAUDE_INBOX/new/" 2>/dev/null || true
    done
    rmdir "$cur_dir" 2>/dev/null || true
}
