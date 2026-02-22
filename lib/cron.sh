#!/bin/bash
# lib/cron.sh: Cron schedule matching and job parsing
#
# Sourced by bin/claude-inbox-cron. Separated for testability.

: "${CLAUDE_INBOX:?CLAUDE_INBOX is not set}"

SCHEDULE_DIR="$CLAUDE_INBOX/schedule"
CRON_STATE_DIR="$SCHEDULE_DIR/state/cron"

# --- Parse a .job file into shell variables ---
# Sets: job_name, job_schedule, job_prompt, job_channel,
#       job_chat_id, job_priority, job_model
parse_job() {
    local job_file="$1"
    job_name="" job_schedule="" job_prompt="" job_channel=""
    job_chat_id="" job_priority=5 job_model=""

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | tr -d '[:space:]')
        case "$key" in
            name)     job_name="$value" ;;
            schedule) job_schedule="$value" ;;
            prompt)   job_prompt="$value" ;;
            channel)  job_channel="$value" ;;
            chat_id)  job_chat_id="$value" ;;
            priority) job_priority="$value" ;;
            model)    job_model="$value" ;;
        esac
    done < "$job_file"
}

# --- Check if a cron field matches a value ---
# Supports: *, */N, N,M, N-M, literal
_field_matches() {
    local pattern="$1" value="$2"

    [ "$pattern" = "*" ] && return 0

    local item
    for item in ${pattern//,/ }; do
        if [[ "$item" == */* ]]; then
            # Step: */5 or 1-10/2
            local base="${item%/*}"
            local step="${item#*/}"
            if [ "$base" = "*" ]; then
                [ $(( value % step )) -eq 0 ] && return 0
            else
                # range/step: not common, skip for simplicity
                :
            fi
        elif [[ "$item" == *-* ]]; then
            # Range: 1-5
            local lo="${item%-*}" hi="${item#*-}"
            [ "$value" -ge "$lo" ] && [ "$value" -le "$hi" ] && return 0
        else
            # Literal
            [ "$value" -eq "$item" ] 2>/dev/null && return 0
        fi
    done
    return 1
}

# --- Check if a 5-field cron schedule matches the current time ---
# $1: "min hour dom month dow"
cron_matches() {
    local spec="$1"
    local s_min s_hour s_dom s_mon s_dow
    read -r s_min s_hour s_dom s_mon s_dow <<< "$spec"

    _field_matches "$s_min"  "$(date +%-M)" &&
    _field_matches "$s_hour" "$(date +%-H)" &&
    _field_matches "$s_dom"  "$(date +%-d)" &&
    _field_matches "$s_mon"  "$(date +%-m)" &&
    _field_matches "$s_dow"  "$(date +%u)"    # 1=Mon ... 7=Sun
}

# --- Check if a job already ran in the current minute ---
already_ran() {
    local name="$1"
    local last_file="$CRON_STATE_DIR/${name}.last"
    [ -f "$last_file" ] || return 1

    local last_ts now_min_ts
    last_ts=$(cat "$last_file")
    # Truncate current time to minute boundary (seconds=0)
    now_min_ts=$(date -d "$(date +%Y-%m-%dT%H:%M:00)" +%s 2>/dev/null) || {
        # macOS fallback
        now_min_ts=$(date +%s)
        now_min_ts=$(( now_min_ts - now_min_ts % 60 ))
    }
    [ "$last_ts" -ge "$now_min_ts" ] 2>/dev/null
}

# --- Mark a job as executed ---
mark_ran() {
    local name="$1"
    printf '%s\n' "$(date +%s)" > "$CRON_STATE_DIR/${name}.last"
}
