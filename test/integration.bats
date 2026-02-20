#!/usr/bin/env bats
# test/integration.bats: End-to-end pipeline with mock claude

load test_helper/common
load test_helper/mock_claude

ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INBOX_ADD="$ROOT_DIR/bin/claude-inbox-add"

@test "full pipeline: submit -> claim -> execute -> complete" {
    setup_mock_claude 0 "execution result"

    # 1. Submit via inbox-add
    run "$INBOX_ADD" "collect news"
    [ "$status" -eq 0 ]
    [ "$(ls "$CLAUDE_INBOX/new/"*.task | wc -l)" -eq 1 ]

    # 2. Claim
    local claimed
    claimed=$(task_claim "int-worker")
    [ -f "$claimed" ]
    [ "$(cat "$claimed")" = "collect news" ]

    # 3. Execute mock claude
    local result
    result=$(claude -p "$(cat "$claimed")" --dangerously-skip-permissions 2>&1)
    [ "$result" = "execution result" ]

    # 4. Complete
    task_complete "$claimed" "$result"

    local bname
    bname=$(basename "$claimed")
    local id="${bname%.task}"
    [ -f "$CLAUDE_INBOX/done/$bname" ]
    [ -f "$CLAUDE_INBOX/done/$id.result" ]
    [ "$(cat "$CLAUDE_INBOX/done/$id.result")" = "execution result" ]
}

@test "full pipeline: failed task goes to failed/" {
    setup_mock_claude 1 "error output"

    "$INBOX_ADD" "will fail" >/dev/null
    local claimed
    claimed=$(task_claim "int-worker")

    local rc=0
    local result
    result=$(claude -p "$(cat "$claimed")" --dangerously-skip-permissions 2>&1) || rc=$?
    [ "$rc" -eq 1 ]

    task_fail "$claimed" "$result"

    local bname
    bname=$(basename "$claimed")
    local id="${bname%.task}"
    [ -f "$CLAUDE_INBOX/failed/$bname" ]
    [ -f "$CLAUDE_INBOX/failed/$id.result" ]
}

@test "pipeline with metadata: session_id preserved through lifecycle" {
    setup_mock_claude 0 "session result"

    # Submit with metadata (simulating inbox-recv)
    local prompt="[from=TestUser channel=telegram chat_id=999 msg_id=42 session_id=test-uuid-123]

do something"
    task_submit --prompt "$prompt" >/dev/null

    local claimed
    claimed=$(task_claim "int-worker")
    local content
    content=$(cat "$claimed")

    # Extract metadata
    local session_id
    session_id=$(echo "$content" | head -1 | grep -oP 'session_id=\K[^ \]]*' || true)
    [ "$session_id" = "test-uuid-123" ]

    local chat_id
    chat_id=$(echo "$content" | head -1 | grep -oP 'chat_id=\K[^ \]]*' || true)
    [ "$chat_id" = "999" ]

    task_complete "$claimed" "session result"
}

@test "pipeline: recover after crash restores tasks" {
    "$INBOX_ADD" "task1" >/dev/null
    "$INBOX_ADD" "task2" >/dev/null

    # Worker claims both
    local c1 c2
    c1=$(task_claim "crash-worker")
    c2=$(task_claim "crash-worker")

    # Simulate crash: tasks stuck in cur/
    [ -f "$c1" ]
    [ -f "$c2" ]
    [ "$(ls "$CLAUDE_INBOX/new/"*.task 2>/dev/null | wc -l)" -eq 0 ]

    # Recover
    task_recover "crash-worker"

    # Tasks back in new/
    [ "$(ls "$CLAUDE_INBOX/new/"*.task | wc -l)" -eq 2 ]
    [ ! -d "$CLAUDE_INBOX/cur/crash-worker" ]
}
