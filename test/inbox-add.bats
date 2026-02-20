#!/usr/bin/env bats
# test/inbox-add.bats: Tests for bin/claude-inbox-add CLI

load test_helper/common

ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INBOX_ADD="$ROOT_DIR/bin/claude-inbox-add"

@test "inbox-add creates task with default priority 5" {
    run "$INBOX_ADD" "test prompt"
    [ "$status" -eq 0 ]
    [[ "$output" == submitted:* ]]

    local files
    files=$(ls "$CLAUDE_INBOX/new/"*.task 2>/dev/null)
    [ -n "$files" ]

    local bname
    bname=$(basename $files .task)
    [[ "$bname" == 5.* ]]
}

@test "inbox-add --priority sets priority" {
    run "$INBOX_ADD" --priority 1 "urgent task"
    [ "$status" -eq 0 ]

    local bname
    bname=$(basename "$CLAUDE_INBOX/new/"*.task .task)
    [[ "$bname" == 1.* ]]
}

@test "inbox-add reads from stdin" {
    run bash -c "echo 'stdin prompt' | CLAUDE_INBOX='$CLAUDE_INBOX' '$INBOX_ADD'"
    [ "$status" -eq 0 ]

    local content
    content=$(cat "$CLAUDE_INBOX/new/"*.task)
    [[ "$content" == *"stdin prompt"* ]]
}

@test "inbox-add fails on empty input" {
    run bash -c "echo '' | CLAUDE_INBOX='$CLAUDE_INBOX' '$INBOX_ADD' < /dev/null"
    [ "$status" -ne 0 ]
}

@test "inbox-add --help prints usage and exits 0" {
    run "$INBOX_ADD" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "inbox-add task content contains input prompt" {
    "$INBOX_ADD" "my specific prompt" >/dev/null
    local content
    content=$(cat "$CLAUDE_INBOX/new/"*.task)
    [[ "$content" == *"my specific prompt"* ]]
    [[ "$content" == *"channel=cli"* ]]
    [[ "$content" == *"workdir="* ]]
}
