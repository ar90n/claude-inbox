#!/usr/bin/env bats
# test/concurrency.bats: Multi-worker stress test for mv(2) atomicity

load test_helper/common

@test "concurrent claim: 20 tasks, 3 workers, zero duplicates" {
    # Submit 20 tasks
    for i in $(seq 1 20); do
        task_submit --prompt "task-$i" >/dev/null
    done
    [ "$(ls "$CLAUDE_INBOX/new/" | wc -l)" -eq 20 ]

    # Run 3 concurrent claim loops
    claim_loop() {
        local wid="$1"
        while true; do
            local f
            f=$(task_claim "$wid") || break
            # Simulate work then complete
            task_complete "$f" "result by $wid"
        done
    }

    claim_loop "w1" &
    local pid1=$!
    claim_loop "w2" &
    local pid2=$!
    claim_loop "w3" &
    local pid3=$!

    wait $pid1 $pid2 $pid3

    # All 20 tasks should be in done/
    local done_tasks
    done_tasks=$(ls "$CLAUDE_INBOX/done/"*.task 2>/dev/null | wc -l)
    local done_results
    done_results=$(ls "$CLAUDE_INBOX/done/"*.result 2>/dev/null | wc -l)

    [ "$done_tasks" -eq 20 ]
    [ "$done_results" -eq 20 ]

    # new/ should be empty
    local remaining
    remaining=$(ls "$CLAUDE_INBOX/new/"*.task 2>/dev/null | wc -l)
    [ "$remaining" -eq 0 ]

    # No duplicates: each task basename should appear exactly once in done/
    local unique_count
    unique_count=$(ls "$CLAUDE_INBOX/done/"*.task | xargs -n1 basename | sort -u | wc -l)
    [ "$unique_count" -eq 20 ]
}

@test "concurrent claim: no task lost when workers race" {
    # Submit 5 tasks
    for i in $(seq 1 5); do
        task_submit --prompt "race-$i" >/dev/null
    done

    # 5 workers race to claim 5 tasks
    for wid in w1 w2 w3 w4 w5; do
        (
            while true; do
                f=$(task_claim "$wid") || break
                task_complete "$f" "done by $wid"
            done
        ) &
    done
    wait

    local total
    total=$(ls "$CLAUDE_INBOX/done/"*.task 2>/dev/null | wc -l)
    [ "$total" -eq 5 ]
}
