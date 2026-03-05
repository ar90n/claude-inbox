#!/bin/bash
# lib/util.sh: Shared utility functions
#
# Sourced by daemons that need session ID generation or filesystem event waiting.

# --- Deterministic session ID (uuid5) ---
# Same input always produces the same UUID. Used by bridge, cron, url-watch.
# Usage: generate_session_id "telegram:12345"
generate_session_id() {
    python3 -c "import uuid,sys; print(uuid.uuid5(uuid.NAMESPACE_URL, sys.argv[1]))" "$1"
}

# --- Wait for filesystem events in a directory ---
# Blocks up to $2 seconds (default 5) until a file appears in $1.
# Uses inotifywait > fswatch > sleep fallback chain.
wait_for_events() {
    local dir="$1"
    local timeout="${2:-5}"

    if command -v inotifywait &>/dev/null; then
        inotifywait -qq -r -e moved_to -e create -t "$timeout" "$dir" 2>/dev/null || true
    elif command -v fswatch &>/dev/null; then
        timeout "$timeout" fswatch --one-event --latency=0.5 "$dir" 2>/dev/null || true
    else
        sleep 2
    fi
}
