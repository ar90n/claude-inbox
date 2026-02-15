#!/bin/bash
# test/test_helper/common.bash: Shared setup for all bats tests
#
# Creates an isolated temp CLAUDE_INBOX per test and sources lib/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setup() {
    export CLAUDE_INBOX="$(mktemp -d)"
    mkdir -p "$CLAUDE_INBOX"/{tmp,new,cur,done,failed,state}
    source "$ROOT_DIR/lib/task.sh"
}

teardown() {
    [ -d "$CLAUDE_INBOX" ] && rm -rf "$CLAUDE_INBOX"
}
