#!/usr/bin/env bats
# test/worker.bats: Tests for worker's run_claude() resume fallback logic

load test_helper/common
load test_helper/mock_claude

ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    export CLAUDE_INBOX="$(mktemp -d)"
    mkdir -p "$CLAUDE_INBOX"/{tmp,new,cur,done,failed,state}
    source "$ROOT_DIR/lib/task.sh"
    source "$ROOT_DIR/lib/observe.sh"

    # Source run_claude from worker by extracting it
    # We define it inline to isolate from the worker's main loop
    system_prompt=""
    SYSTEM="$CLAUDE_INBOX/system.md"
    SKILLS_DIR="$CLAUDE_INBOX/skills"
    WORKDIR=""

    run_claude() {
        local prompt="$1" session_id="$2"
        local common_args=(-p "$prompt" --dangerously-skip-permissions)
        [ -n "$system_prompt" ] && common_args+=(--system-prompt "$system_prompt")
        [ -d "$SKILLS_DIR" ] && common_args+=(--add-dir "$SKILLS_DIR")

        local run_cmd="claude"
        local result="" rc=0

        if [ -n "$session_id" ]; then
            result=$($run_cmd --resume "$session_id" "${common_args[@]}" 2>&1) && {
                echo "$result"
                return 0
            }
            result=$($run_cmd --session-id "$session_id" "${common_args[@]}" 2>&1) || rc=$?
        else
            result=$($run_cmd "${common_args[@]}" 2>&1) || rc=$?
        fi

        echo "$result"
        return $rc
    }
}

teardown() {
    teardown_mock_claude
    [ -d "$CLAUDE_INBOX" ] && rm -rf "$CLAUDE_INBOX"
}

# --- Resume fallback ---

@test "session_id present: tries --resume first" {
    setup_mock_claude 0 "resumed ok"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 0 ]
    [ "$output" = "resumed ok" ]

    # First call should have --resume
    local first_call
    first_call=$(head -1 "$MOCK_CLAUDE_LOG")
    [[ "$first_call" == *"--resume test-session-id"* ]]
}

@test "--resume fails: falls back to --session-id" {
    setup_mock_claude_resume_fallback "fallback ok"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 0 ]

    # Should have 2 calls: first --resume (failed), then --session-id
    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 2 ]

    local second_call
    second_call=$(sed -n '2p' "$MOCK_CLAUDE_LOG")
    [[ "$second_call" == *"--session-id test-session-id"* ]]
}

@test "no session_id: runs without session flags" {
    setup_mock_claude 0 "no session"

    run run_claude "hello" ""
    [ "$status" -eq 0 ]
    [ "$output" = "no session" ]

    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" != *"--resume"* ]]
    [[ "$call" != *"--session-id"* ]]
}

@test "--dangerously-skip-permissions always included" {
    setup_mock_claude 0 "ok"

    run_claude "hello" "" >/dev/null
    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" == *"--dangerously-skip-permissions"* ]]
}

@test "--system-prompt included when system.md exists" {
    setup_mock_claude 0 "ok"
    echo "You are an agent" > "$CLAUDE_INBOX/system.md"
    system_prompt="You are an agent"

    run_claude "hello" "" >/dev/null
    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" == *"--system-prompt"* ]]
}

@test "--system-prompt omitted when system.md missing" {
    setup_mock_claude 0 "ok"
    system_prompt=""

    run_claude "hello" "" >/dev/null
    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" != *"--system-prompt"* ]]
}

@test "--add-dir included when skills/ exists" {
    setup_mock_claude 0 "ok"
    mkdir -p "$SKILLS_DIR"

    run_claude "hello" "" >/dev/null
    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" == *"--add-dir"* ]]
}

@test "--add-dir omitted when skills/ missing" {
    setup_mock_claude 0 "ok"
    # SKILLS_DIR does not exist (not created)
    SKILLS_DIR="$CLAUDE_INBOX/nonexistent-skills"

    run_claude "hello" "" >/dev/null
    local call
    call=$(cat "$MOCK_CLAUDE_LOG")
    [[ "$call" != *"--add-dir"* ]]
}
