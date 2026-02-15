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

@test "task_claim moves oldest task from new/ to cur/{wid}/" {
    task_submit --prompt "first" --priority 1 >/dev/null
    sleep 1
    task_submit --prompt "second" --priority 5 >/dev/null

    run task_claim "test-worker"
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    [[ "$output" == */cur/test-worker/* ]]
    [ "$(cat "$output")" = "first" ]
}

@test "task_claim returns 1 when new/ is empty" {
    run task_claim "test-worker"
    [ "$status" -eq 1 ]
}

@test "task_claim returns file path on success" {
    task_submit --prompt "test" >/dev/null
    run task_claim "test-worker"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ -f "$output" ]
}

# --- task_complete ---

@test "task_complete moves task to done/ and creates .result" {
    local path
    path=$(task_submit --prompt "do this")
    local claimed
    claimed=$(task_claim "test-worker")

    task_complete "$claimed" "done result"

    local bname
    bname=$(basename "$claimed")
    local id="${bname%.task}"

    [ -f "$CLAUDE_INBOX/done/$bname" ]
    [ -f "$CLAUDE_INBOX/done/$id.result" ]
    [ ! -f "$claimed" ]
}

@test "task_complete result content matches input" {
    local path
    path=$(task_submit --prompt "do this")
    local claimed
    claimed=$(task_claim "test-worker")

    task_complete "$claimed" "my result text"

    local bname
    bname=$(basename "$claimed")
    local id="${bname%.task}"

    [ "$(cat "$CLAUDE_INBOX/done/$id.result")" = "my result text" ]
}

@test "task_complete fails on missing task file" {
    run task_complete "/nonexistent/file.task" "result"
    [ "$status" -eq 2 ]
}

# --- task_fail ---

@test "task_fail moves task to failed/ and creates .result" {
    local path
    path=$(task_submit --prompt "will fail")
    local claimed
    claimed=$(task_claim "test-worker")

    task_fail "$claimed" "error message"

    local bname
    bname=$(basename "$claimed")
    local id="${bname%.task}"

    [ -f "$CLAUDE_INBOX/failed/$bname" ]
    [ -f "$CLAUDE_INBOX/failed/$id.result" ]
    [ ! -f "$claimed" ]
    [ "$(cat "$CLAUDE_INBOX/failed/$id.result")" = "error message" ]
}

@test "task_fail fails on missing task file" {
    run task_fail "/nonexistent/file.task" "error"
    [ "$status" -eq 2 ]
}

# --- task_recover ---

@test "task_recover moves orphaned tasks from cur/{wid}/ back to new/" {
    local path
    path=$(task_submit --prompt "orphan")
    local claimed
    claimed=$(task_claim "dead-worker")

    local bname
    bname=$(basename "$claimed")

    task_recover "dead-worker"

    [ -f "$CLAUDE_INBOX/new/$bname" ]
    [ ! -f "$claimed" ]
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
