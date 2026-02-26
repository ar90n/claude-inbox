#!/bin/bash
# test/test_helper/common.bash: Shared setup for all bats tests
#
# Creates an isolated temp CLAUDE_INBOX per test and sources lib/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setup() {
    export CLAUDE_INBOX="$(mktemp -d)"
    mkdir -p "$CLAUDE_INBOX"/{tmp,new,tasks,cur,done,failed,state}
    source "$ROOT_DIR/lib/task.sh"
}

teardown() {
    [ -d "$CLAUDE_INBOX" ] && rm -rf "$CLAUDE_INBOX"
}

# Helper: create a task directory in tasks/ (simulates preprocessor output)
# Usage: create_task_dir "prompt text" [priority]
# Prints the task directory path
create_task_dir() {
    local prompt="${1:?}" priority="${2:-5}"
    local ts rand job_id task_dir
    ts=$(date +%Y%m%d-%H%M%S)
    rand=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    job_id="${priority}.${ts}.${rand}"
    task_dir="$CLAUDE_INBOX/tasks/$job_id"
    mkdir -p "$task_dir"
    printf '%s\n' "$prompt" > "$task_dir/prompt.txt"
    echo "$task_dir"
}
