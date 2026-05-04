#!/usr/bin/env bash
# Claude Code status line script
# Usage: statusline.sh [LABEL]   (LABEL defaults to WORK)
# Outputs: LABEL (bold) | ctx% | 5h% (±delta%) | 7d% (±delta%) | worktree | PR#NNNN | model

set -euo pipefail

# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
BRIGHT_YELLOW='\033[1;33m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_BLUE='\033[1;34m'
MAGENTA='\033[35m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM_GRAY='\033[2;37m'

LABEL="${1:-WORK}"
case "$LABEL" in
    WORK)     LABEL_COLOR="$BRIGHT_YELLOW" ;;
    PERSONAL) LABEL_COLOR="$BRIGHT_GREEN" ;;
    *)        LABEL_COLOR="$BOLD" ;;
esac

# Returns an ANSI color code based on a percentage threshold.
# <50% -> green, 50-80% -> yellow, >80% -> red
pct_color() {
    local val="$1"  # numeric percentage, no % sign
    if [ "$val" -lt 50 ] 2>/dev/null; then
        printf '%s' "$GREEN"
    elif [ "$val" -lt 80 ] 2>/dev/null; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$RED"
    fi
}

input=$(cat)

# Write first-seen input to sample file for schema inspection.
[ -f /tmp/claude_statusline_sample.json ] || printf '%s\n' "$input" > /tmp/claude_statusline_sample.json

# Extract fields from JSON input
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
model_display=$(printf '%s' "$input" | jq -r '.model.display_name // "unknown"')
model_id=$(printf '%s' "$input" | jq -r '.model.id // ""')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
git_worktree=$(printf '%s' "$input" | jq -r '.workspace.git_worktree // empty')

# Determine context window size
if printf '%s' "$model_id" | grep -q '\[1m\]'; then
    ctx_window=1000000
else
    ctx_window=200000
fi

# Compute context usage % from transcript JSONL
ctx_pct="-"
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    usage_json=$(grep -o '"usage":{[^}]*}' "$transcript_path" 2>/dev/null | tail -1 || true)
    if [ -n "$usage_json" ]; then
        input_tokens=$(printf '%s' "$usage_json" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*' || echo 0)
        cache_read=$(printf '%s' "$usage_json" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*' || echo 0)
        cache_creation=$(printf '%s' "$usage_json" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*' || echo 0)
        total_tokens=$(( ${input_tokens:-0} + ${cache_read:-0} + ${cache_creation:-0} ))
        if [ "$total_tokens" -gt 0 ] 2>/dev/null; then
            ctx_pct=$(awk "BEGIN { printf \"%.0f\", ($total_tokens / $ctx_window) * 100 }")%
        fi
    fi
fi

# Extract pre-calculated context % from JSON input (fallback for live usage)
if [ "$ctx_pct" = "-" ]; then
    used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
    if [ -n "$used_pct" ]; then
        ctx_pct=$(printf '%.0f' "$used_pct")%
    fi
fi

# 5-hour and 7-day usage from JSON input (provided by Claude Code)
# Also compute pace delta: used_percentage - time_elapsed_percentage.
# Window start = resets_at - window_length; time_elapsed % = (now - window_start) / window_length * 100.
# Delta coloring: <= -5 green (under pace), -5..+5 dim gray (on pace), >= +5 red (over pace).

# pace_delta_suffix <used_pct_int> <resets_at_str> <window_seconds>
# Prints a colored " (+D%)" suffix, or nothing on failure.
pace_delta_suffix() {
    local used_pct="$1"
    local resets_at="$2"
    local window_secs="$3"

    [ -z "$resets_at" ] && return 0

    local reset_epoch
    if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
        reset_epoch="$resets_at"
    else
        reset_epoch=$(date -d "$resets_at" +%s 2>/dev/null) || return 0
    fi

    local now
    now=$(date +%s)

    local window_start=$(( reset_epoch - window_secs ))
    local elapsed=$(( now - window_start ))

    # Guard against negative elapsed or elapsed > window (clock skew / already-reset window).
    if [ "$elapsed" -le 0 ] || [ "$elapsed" -gt "$window_secs" ]; then
        return 0
    fi

    # time_elapsed_pct and delta computed with awk for float arithmetic.
    local delta
    delta=$(awk "BEGIN { printf \"%.0f\", $used_pct - ($elapsed / $window_secs * 100) }")

    local col
    if [ "$delta" -le -5 ] 2>/dev/null; then
        col="$GREEN"
    elif [ "$delta" -ge 5 ] 2>/dev/null; then
        col="$RED"
    else
        col="$DIM_GRAY"
    fi

    local sign=""
    [ "$delta" -ge 0 ] 2>/dev/null && sign="+"

    printf '%b' " ${col}(${sign}${delta}pp)${RESET}"
}

five_hour_pct="-"
seven_day_pct="-"
five_delta_suffix=""

five_raw=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets_at=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_raw=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_resets_at=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$five_raw" ]; then
    five_int=$(printf '%.0f' "$five_raw")
    five_hour_pct="${five_int}%"
    five_delta_suffix=$(pace_delta_suffix "$five_int" "$five_resets_at" 18000)
fi
if [ -n "$seven_raw" ]; then
    seven_int=$(printf '%.0f' "$seven_raw")
    seven_day_pct="${seven_int}%"
    # Weekly limit is a rolling 7d window; resets_at reflects when the oldest
    # recorded usage ages out, not a fixed window start. Pace delta is not
    # meaningful here, so we omit it.
fi

# Determine worktree name: prefer git_worktree field, else basename of cwd
worktree_name="-"
if [ -n "$git_worktree" ]; then
    worktree_name="$git_worktree"
elif [ -n "$cwd" ]; then
    worktree_name=$(basename "$cwd")
fi

# Look up PR for the current branch, with per-branch caching (TTL 60s)
pr_field=""
if [ -n "$cwd" ] && command -v gh >/dev/null 2>&1; then
    # Get current branch name to use as cache key
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
        # Sanitize branch name for use as filename
        branch_key=$(printf '%s' "$branch" | tr '/' '_' | tr -cd '[:alnum:]_.-')
        cache_file="/tmp/claude_pr_cache_${branch_key}"
        now=$(date +%s)

        # Check if cache exists and is fresh (< 60s old)
        use_cache=0
        if [ -f "$cache_file" ]; then
            cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
            age=$(( now - cache_mtime ))
            if [ "$age" -lt 60 ]; then
                use_cache=1
            fi
        fi

        if [ "$use_cache" -eq 1 ]; then
            pr_json=$(cat "$cache_file")
        else
            pr_json=$(cd "$cwd" && timeout 1 gh pr view --json number,state,isDraft 2>/dev/null || true)
            # Only write cache if we got a result (empty means no PR or timeout — cache that too)
            printf '%s' "$pr_json" > "$cache_file"
        fi

        if [ -n "$pr_json" ]; then
            pr_number=$(printf '%s' "$pr_json" | jq -r '.number // empty')
            pr_draft=$(printf '%s' "$pr_json" | jq -r '.isDraft // false')
            if [ -n "$pr_number" ]; then
                if [ "$pr_draft" = "true" ]; then
                    pr_field="${MAGENTA}PR#${pr_number}${RESET} ${DIM_GRAY}(draft)${RESET}"
                else
                    pr_field="${MAGENTA}PR#${pr_number}${RESET}"
                fi
            fi
        fi
    fi
fi

# Color the ctx, 5h, 7d values by threshold; dash values get dim gray.
# Strip trailing % to get the numeric part for threshold comparison.
color_pct_field() {
    local val="$1"
    if [ "$val" = "-" ]; then
        printf '%b' "${DIM_GRAY}-${RESET}"
    else
        local num="${val%%%}"  # remove trailing %
        local col
        col=$(pct_color "$num")
        printf '%b' "${col}${val}${RESET}"
    fi
}

ctx_colored=$(color_pct_field "$ctx_pct")
five_colored=$(color_pct_field "$five_hour_pct")
seven_colored=$(color_pct_field "$seven_day_pct")

SEP="${DIM_GRAY} | ${RESET}"

# Compose status line
if [ -n "$pr_field" ]; then
    printf '%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b' \
        "${LABEL_COLOR}${LABEL}${RESET}" \
        "$SEP" \
        "${CYAN}ctx:${RESET}" "$ctx_colored" \
        "$SEP" \
        "${CYAN}5h:${RESET}" "$five_colored" "$five_delta_suffix" \
        "$SEP" \
        "${CYAN}7d:${RESET}" "$seven_colored" \
        "$SEP" \
        "${BRIGHT_BLUE}${worktree_name}${RESET}" \
        "$SEP" \
        "$pr_field" \
        "$SEP" \
        "${DIM_GRAY}${model_display}${RESET}" \
        "${RESET}"
else
    printf '%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b' \
        "${LABEL_COLOR}${LABEL}${RESET}" \
        "$SEP" \
        "${CYAN}ctx:${RESET}" "$ctx_colored" \
        "$SEP" \
        "${CYAN}5h:${RESET}" "$five_colored" "$five_delta_suffix" \
        "$SEP" \
        "${CYAN}7d:${RESET}" "$seven_colored" \
        "$SEP" \
        "${BRIGHT_BLUE}${worktree_name}${RESET}" \
        "$SEP" \
        "${DIM_GRAY}${model_display}${RESET}" \
        "${RESET}"
fi
