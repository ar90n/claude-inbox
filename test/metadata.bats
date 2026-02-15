#!/usr/bin/env bats
# test/metadata.bats: Tests for extract_meta and generate_session_id

load test_helper/common

setup() {
    # Call parent setup for CLAUDE_INBOX
    export CLAUDE_INBOX="$(mktemp -d)"
    mkdir -p "$CLAUDE_INBOX"/{tmp,new,cur,done,failed,state}

    # Source extract_meta from worker (define inline since it's not in lib/)
    extract_meta() {
        local content="$1" key="$2"
        echo "$content" | head -1 | grep -oP "${key}=\K[^ \]]*" || true
    }
    export -f extract_meta

    # Source generate_session_id from inbox-recv
    generate_session_id() {
        python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, '$1'))"
    }
    export -f generate_session_id
}

teardown() {
    [ -d "$CLAUDE_INBOX" ] && rm -rf "$CLAUDE_INBOX"
}

# --- extract_meta ---

@test "extract_meta extracts session_id" {
    local line="[from=User channel=telegram chat_id=12345 msg_id=200 session_id=abc-123]"
    run extract_meta "$line" "session_id"
    [ "$status" -eq 0 ]
    [ "$output" = "abc-123" ]
}

@test "extract_meta extracts chat_id" {
    local line="[from=User channel=telegram chat_id=12345 msg_id=200 session_id=abc-123]"
    run extract_meta "$line" "chat_id"
    [ "$output" = "12345" ]
}

@test "extract_meta extracts msg_id" {
    local line="[from=User channel=telegram chat_id=12345 msg_id=200 session_id=abc-123]"
    run extract_meta "$line" "msg_id"
    [ "$output" = "200" ]
}

@test "extract_meta extracts from" {
    local line="[from=UserName channel=telegram chat_id=12345 msg_id=200 session_id=abc-123]"
    run extract_meta "$line" "from"
    [ "$output" = "UserName" ]
}

@test "extract_meta returns empty for missing key" {
    local line="[from=User channel=telegram chat_id=12345]"
    run extract_meta "$line" "session_id"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_meta only parses first line" {
    local content="[from=User session_id=first-line]
[session_id=second-line]
some body text"
    run extract_meta "$content" "session_id"
    [ "$output" = "first-line" ]
}

# --- generate_session_id ---

@test "generate_session_id is deterministic" {
    local id1 id2
    id1=$(generate_session_id "telegram:12345")
    id2=$(generate_session_id "telegram:12345")
    [ "$id1" = "$id2" ]
}

@test "generate_session_id: different input produces different UUID" {
    local id1 id2
    id1=$(generate_session_id "telegram:12345")
    id2=$(generate_session_id "telegram:67890")
    [ "$id1" != "$id2" ]
}

@test "generate_session_id output is valid UUID format" {
    run generate_session_id "telegram:12345"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "generate_session_id produces uuid5 (version 5)" {
    run generate_session_id "telegram:12345"
    # UUID v5 has version nibble = 5 at position 13
    [[ "${output:14:1}" == "5" ]]
}
