#!/usr/bin/env bats
# test/integration.bats: End-to-end pipeline with mock claude

load test_helper/common
load test_helper/mock_claude

ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INBOX_ADD="$ROOT_DIR/bin/claude-inbox-add"

@test "full pipeline: create task dir -> claim -> execute -> complete" {
    setup_mock_claude 0 "execution result"

    # 1. Create task directory (simulates preprocessor output)
    local task_dir
    task_dir=$(create_task_dir "collect news")
    [ -d "$task_dir" ]

    # 2. Claim
    local claimed
    claimed=$(task_claim "int-worker")
    [ -d "$claimed" ]
    [[ "$(cat "$claimed/prompt.txt")" == *"collect news"* ]]

    # 3. Execute mock claude
    local result
    result=$(claude -p "$(cat "$claimed/prompt.txt")" --dangerously-skip-permissions 2>&1)
    [ "$result" = "execution result" ]

    # 4. Complete
    task_complete "$claimed" "$result"

    local job_id
    job_id=$(basename "$claimed")
    [ -d "$CLAUDE_INBOX/done/$job_id" ]
    [ -f "$CLAUDE_INBOX/done/$job_id/result" ]
    [ "$(cat "$CLAUDE_INBOX/done/$job_id/result")" = "execution result" ]
}

@test "full pipeline: failed task goes to failed/" {
    setup_mock_claude 1 "error output"

    create_task_dir "will fail" >/dev/null
    local claimed
    claimed=$(task_claim "int-worker")

    local rc=0
    local result
    result=$(claude -p "$(cat "$claimed/prompt.txt")" --dangerously-skip-permissions 2>&1) || rc=$?
    [ "$rc" -eq 1 ]

    task_fail "$claimed" "$result"

    local job_id
    job_id=$(basename "$claimed")
    [ -d "$CLAUDE_INBOX/failed/$job_id" ]
    [ -f "$CLAUDE_INBOX/failed/$job_id/result" ]
}

@test "pipeline with metadata: session_id preserved through lifecycle" {
    setup_mock_claude 0 "session result"

    # Create task directory with metadata (simulates preprocessor output)
    local task_dir
    task_dir=$(create_task_dir "do something")
    cat > "$task_dir/meta" <<'EOF'
from=TestUser
channel=telegram
chat_id=999
msg_id=42
session_id=test-uuid-123
EOF

    local claimed
    claimed=$(task_claim "int-worker")

    # Read metadata from meta file
    local session_id
    session_id=$(grep -oP '^session_id=\K.*' "$claimed/meta" || true)
    [ "$session_id" = "test-uuid-123" ]

    local chat_id
    chat_id=$(grep -oP '^chat_id=\K.*' "$claimed/meta" || true)
    [ "$chat_id" = "999" ]

    task_complete "$claimed" "session result"
}

@test "pipeline: recover after crash restores tasks" {
    create_task_dir "task1" >/dev/null
    create_task_dir "task2" >/dev/null

    # Worker claims both
    local c1 c2
    c1=$(task_claim "crash-worker")
    c2=$(task_claim "crash-worker")

    # Simulate crash: tasks stuck in cur/
    [ -d "$c1" ]
    [ -d "$c2" ]
    local remaining
    remaining=$(find "$CLAUDE_INBOX/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    [ "$remaining" -eq 0 ]

    # Recover
    task_recover "crash-worker"

    # Tasks back in tasks/
    local recovered
    recovered=$(find "$CLAUDE_INBOX/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    [ "$recovered" -eq 2 ]
    [ ! -d "$CLAUDE_INBOX/cur/crash-worker" ]
}
