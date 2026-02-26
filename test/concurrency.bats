#!/usr/bin/env bats
# test/concurrency.bats: Multi-worker stress test for mv(2) atomicity

load test_helper/common

@test "concurrent claim: 20 tasks, 3 workers, zero duplicates" {
    # Create 20 task directories
    for i in $(seq 1 20); do
        create_task_dir "task-$i" >/dev/null
    done
    local task_count
    task_count=$(find "$CLAUDE_INBOX/tasks" -mindepth 1 -maxdepth 1 -type d | wc -l)
    [ "$task_count" -eq 20 ]

    # Run 3 concurrent claim loops
    claim_loop() {
        local wid="$1"
        while true; do
            local d
            d=$(task_claim "$wid") || break
            # Simulate work then complete
            task_complete "$d" "result by $wid"
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
    done_tasks=$(find "$CLAUDE_INBOX/done" -mindepth 1 -maxdepth 1 -type d | wc -l)

    [ "$done_tasks" -eq 20 ]

    # tasks/ should be empty
    local remaining
    remaining=$(find "$CLAUDE_INBOX/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    [ "$remaining" -eq 0 ]

    # No duplicates: each job_id should appear exactly once in done/
    local unique_count
    unique_count=$(ls "$CLAUDE_INBOX/done/" | sort -u | wc -l)
    [ "$unique_count" -eq 20 ]
}

@test "concurrent claim: no task lost when workers race" {
    # Create 5 task directories
    for i in $(seq 1 5); do
        create_task_dir "race-$i" >/dev/null
    done

    # 5 workers race to claim 5 tasks
    for wid in w1 w2 w3 w4 w5; do
        (
            while true; do
                d=$(task_claim "$wid") || break
                task_complete "$d" "done by $wid"
            done
        ) &
    done
    wait

    local total
    total=$(find "$CLAUDE_INBOX/done" -mindepth 1 -maxdepth 1 -type d | wc -l)
    [ "$total" -eq 5 ]
}
