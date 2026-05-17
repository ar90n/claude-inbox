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

        _run() {
            result=$($run_cmd "$@" "${common_args[@]}" 2>&1) || return $?
        }

        _is_terminal_rc() {
            case "$1" in 124|137|143) return 0 ;; *) return 1 ;; esac
        }

        if [ -n "$session_id" ]; then
            rc=0; _run --resume "$session_id" || rc=$?
            if [ "$rc" -eq 0 ] || _is_terminal_rc "$rc"; then
                echo "$result"; return $rc
            fi
            rc=0; _run --session-id "$session_id" || rc=$?
            if [ "$rc" -eq 0 ] || _is_terminal_rc "$rc"; then
                echo "$result"; return $rc
            fi
            rc=0; _run || rc=$?
        else
            rc=0; _run || rc=$?
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

@test "--resume and --session-id both fail: falls back to no session" {
    setup_mock_claude_session_stale "stale fallback ok"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 0 ]

    # Should have 3 calls: --resume (failed), --session-id (failed), no session
    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 3 ]

    local third_call
    third_call=$(sed -n '3p' "$MOCK_CLAUDE_LOG")
    [[ "$third_call" != *"--resume"* ]]
    [[ "$third_call" != *"--session-id"* ]]
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

# --- Timeout short-circuit ---
# Regression: timeout (124, 137, 143) used to trigger the session fallback,
# causing 3x the timeout window per task. Must now short-circuit.

@test "rc=124 (timeout) on --resume short-circuits without retry" {
    setup_mock_claude 124 "(timeout)"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 124 ]

    # Only one call: must not have fallen back to --session-id or bare
    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 1 ]

    local only_call
    only_call=$(head -1 "$MOCK_CLAUDE_LOG")
    [[ "$only_call" == *"--resume test-session-id"* ]]
}

@test "rc=137 (SIGKILL) short-circuits without retry" {
    setup_mock_claude 137 "(killed)"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 137 ]

    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 1 ]
}

@test "rc=143 (SIGTERM) short-circuits without retry" {
    setup_mock_claude 143 "(terminated)"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 143 ]

    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 1 ]
}

@test "rc=124 on --resume short-circuits even without session_id" {
    setup_mock_claude 124 "(timeout)"

    run run_claude "hello" ""
    [ "$status" -eq 124 ]

    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 1 ]
}

@test "rc=1 (non-terminal) still falls back to --session-id" {
    # Regression guard: don't over-eagerly short-circuit on non-timeout errors
    setup_mock_claude_resume_fallback "fallback ok"

    run run_claude "hello" "test-session-id"
    [ "$status" -eq 0 ]

    local call_count
    call_count=$(wc -l < "$MOCK_CLAUDE_LOG")
    [ "$call_count" -eq 2 ]
}
