#!/bin/bash
# test/test_helper/mock_claude.bash: Stub claude CLI for worker tests
#
# Creates a mock 'claude' script in a temp directory and prepends it to PATH.
# The mock logs all arguments to a file and exits with a configurable code.
#
# Usage in tests:
#   setup_mock_claude           # default: exit 0, output "mock result"
#   setup_mock_claude 1         # exit 1
#   setup_mock_claude 0 "text"  # exit 0, output "text"

setup_mock_claude() {
    local exit_code="${1:-0}"
    local output="${2:-mock result}"

    export MOCK_CLAUDE_DIR="$(mktemp -d)"
    export MOCK_CLAUDE_LOG="$MOCK_CLAUDE_DIR/calls.log"

    cat > "$MOCK_CLAUDE_DIR/claude" <<SCRIPT
#!/bin/bash
echo "\$@" >> "$MOCK_CLAUDE_LOG"
echo "$output"
exit $exit_code
SCRIPT
    chmod +x "$MOCK_CLAUDE_DIR/claude"
    export PATH="$MOCK_CLAUDE_DIR:$PATH"
}

# Setup a mock that fails on --resume but succeeds on --session-id
setup_mock_claude_resume_fallback() {
    local output="${1:-mock result}"

    export MOCK_CLAUDE_DIR="$(mktemp -d)"
    export MOCK_CLAUDE_LOG="$MOCK_CLAUDE_DIR/calls.log"

    cat > "$MOCK_CLAUDE_DIR/claude" <<'SCRIPT'
#!/bin/bash
LOG_FILE="$(dirname "$0")/calls.log"
echo "$@" >> "$LOG_FILE"
for arg in "$@"; do
    if [ "$arg" = "--resume" ]; then
        echo "Error: session not found" >&2
        exit 1
    fi
done
echo "mock result"
exit 0
SCRIPT
    chmod +x "$MOCK_CLAUDE_DIR/claude"
    export PATH="$MOCK_CLAUDE_DIR:$PATH"
}

teardown_mock_claude() {
    [ -d "$MOCK_CLAUDE_DIR" ] && rm -rf "$MOCK_CLAUDE_DIR"
}
