#!/usr/bin/env bats
# test/task.bats: Tests for lib/task.sh atomic task operations

load test_helper/common

# --- task_submit ---

@test "task_submit creates file in new/ with correct content" {
    run task_submit --prompt "hello world"
    [ "$status" -eq 0 ]
    local path="$output"
    [ -f "$path" ]
    [[ "$path" == */new/*.task ]]
    [ "$(cat "$path")" = "hello world" ]
}

@test "task_submit respects --priority" {
    task_submit --prompt "low" --priority 9 >/dev/null
    task_submit --prompt "high" --priority 1 >/dev/null

    local files
    files=$(ls "$CLAUDE_INBOX/new/" | sort)
    local first
    first=$(echo "$files" | head -1)
    [[ "$first" == 1.* ]]
}

@test "task_submit task ID format is {priority}.{YYYYMMDD-HHMMSS}.{hex}" {
    run task_submit --prompt "test"
    [ "$status" -eq 0 ]
    local bname
    bname=$(basename "$output" .task)
    [[ "$bname" =~ ^[0-9]\.[0-9]{8}-[0-9]{6}\.[0-9a-f]+$ ]]
}

@test "task_submit default priority is 5" {
    run task_submit --prompt "test"
    local bname
    bname=$(basename "$output" .task)
    [[ "$bname" == 5.* ]]
}

@test "task_submit reads from stdin when --prompt omitted" {
    local path
    path=$(echo "from stdin" | task_submit)
    [ -f "$path" ]
    [ "$(cat "$path")" = "from stdin" ]
}

@test "task_submit fails on empty prompt" {
    run bash -c "echo '' | CLAUDE_INBOX='$CLAUDE_INBOX' bash -c 'source $ROOT_DIR/lib/task.sh && task_submit < /dev/null'"
    [ "$status" -ne 0 ]
}

# --- task_claim ---

@test "task_claim moves oldest task dir from tasks/ to cur/{wid}/" {
    create_task_dir "first" 1 >/dev/null
    sleep 1
    create_task_dir "second" 5 >/dev/null

    run task_claim "test-worker"
    [ "$status" -eq 0 ]
    [ -d "$output" ]
    [[ "$output" == */cur/test-worker/* ]]
    [ "$(cat "$output/prompt.txt")" = "first" ]
}

@test "task_claim returns 1 when tasks/ is empty" {
    run task_claim "test-worker"
    [ "$status" -eq 1 ]
}

@test "task_claim returns directory path on success" {
    create_task_dir "test" >/dev/null
    run task_claim "test-worker"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ -d "$output" ]
}

# --- task_complete ---

@test "task_complete moves task dir to done/ and creates result" {
    create_task_dir "do this" >/dev/null
    local claimed
    claimed=$(task_claim "test-worker")

    task_complete "$claimed" "done result"

    local job_id
    job_id=$(basename "$claimed")

    [ -d "$CLAUDE_INBOX/done/$job_id" ]
    [ -f "$CLAUDE_INBOX/done/$job_id/result" ]
    [ ! -d "$claimed" ]
}

@test "task_complete result content matches input" {
    create_task_dir "do this" >/dev/null
    local claimed
    claimed=$(task_claim "test-worker")

    task_complete "$claimed" "my result text"

    local job_id
    job_id=$(basename "$claimed")

    [ "$(cat "$CLAUDE_INBOX/done/$job_id/result")" = "my result text" ]
}

@test "task_complete fails on missing task dir" {
    run task_complete "/nonexistent/dir" "result"
    [ "$status" -eq 2 ]
}

# --- task_fail ---

@test "task_fail moves task dir to failed/ and creates result" {
    create_task_dir "will fail" >/dev/null
    local claimed
    claimed=$(task_claim "test-worker")

    task_fail "$claimed" "error message"

    local job_id
    job_id=$(basename "$claimed")

    [ -d "$CLAUDE_INBOX/failed/$job_id" ]
    [ -f "$CLAUDE_INBOX/failed/$job_id/result" ]
    [ ! -d "$claimed" ]
    [ "$(cat "$CLAUDE_INBOX/failed/$job_id/result")" = "error message" ]
}

@test "task_fail fails on missing task dir" {
    run task_fail "/nonexistent/dir" "error"
    [ "$status" -eq 2 ]
}

# --- task_recover ---

@test "task_recover moves orphaned task dirs from cur/{wid}/ back to tasks/" {
    create_task_dir "orphan" >/dev/null
    local claimed
    claimed=$(task_claim "dead-worker")

    local job_id
    job_id=$(basename "$claimed")

    task_recover "dead-worker"

    [ -d "$CLAUDE_INBOX/tasks/$job_id" ]
    [ ! -d "$claimed" ]
    [ ! -d "$CLAUDE_INBOX/cur/dead-worker" ]
}

@test "task_recover removes empty cur/{wid}/ directory" {
    mkdir -p "$CLAUDE_INBOX/cur/empty-worker"
    task_recover "empty-worker"
    [ ! -d "$CLAUDE_INBOX/cur/empty-worker" ]
}

@test "task_recover is a no-op when directory is missing" {
    run task_recover "nonexistent-worker"
    [ "$status" -eq 0 ]
}
