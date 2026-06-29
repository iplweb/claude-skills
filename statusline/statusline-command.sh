#!/bin/sh
# Claude Code statusLine — shell identity + 5h block + weekly usage
# Receives JSON on stdin; outputs a single status line.
#
# Tunables (via env):
#   CC_WEEKLY_TOKEN_LIMIT  — weekly token budget for % calc. Default 5B (Max 20x estimate).
#                            Set to 0 to disable % and show raw tokens only.

# Force C locale so printf/awk use '.' as decimal separator regardless of system locale.
export LC_ALL=C

# Default weekly token budget — Max 20x plan estimate (~5B tokens/week incl. cache reads).
# Override via env to match your actual plan or observed rate-limit threshold.
: "${CC_WEEKLY_TOKEN_LIMIT:=5000000000}"

input=$(cat)

# --- Shell identity (bira: user@host  ~/path) ---
user=$(whoami)
host=$(hostname -s)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
home="$HOME"
short_cwd=$(echo "$cwd" | sed "s|^$home|~|")

# --- Git branch (skip optional lock; non-fatal) ---
branch=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# --- 5h block: % of limit + time remaining ---
# --token-limit max: % is relative to your historical max usage in a 5h window.
block_json=$(ccusage blocks --active --json --token-limit max --offline 2>/dev/null)
block_pct=$(echo "$block_json" | jq -r '.blocks[0].tokenLimitStatus.percentUsed // empty' 2>/dev/null)
block_remaining_min=$(echo "$block_json" | jq -r '.blocks[0].projection.remainingMinutes // empty' 2>/dev/null)

# --- Weekly: total tokens (and % if budget env set) ---
this_monday=$(date -v-mon +%Y%m%d 2>/dev/null || date -d "last monday" +%Y%m%d 2>/dev/null)
weekly_json=$(ccusage weekly --json --since "$this_monday" --offline 2>/dev/null)
weekly_tokens=$(echo "$weekly_json" | jq -r '.totals.totalTokens // 0' 2>/dev/null)

# --- Format helpers ---
fmt_pct() {
    # Round to nearest int. Empty -> empty.
    [ -z "$1" ] && return
    printf '%.0f' "$1"
}

fmt_time() {
    # Minutes -> "3h50m" / "45m"
    m="$1"
    [ -z "$m" ] && return
    h=$((m / 60))
    rem=$((m % 60))
    if [ "$h" -gt 0 ]; then
        printf "%dh%02dm" "$h" "$rem"
    else
        printf "%dm" "$rem"
    fi
}

fmt_tokens() {
    # 2819375385 -> "2.8B", 4190496 -> "4.2M"
    t="$1"
    [ -z "$t" ] || [ "$t" = "0" ] && { printf "0"; return; }
    if [ "$t" -ge 1000000000 ]; then
        awk -v t="$t" 'BEGIN { printf "%.1fB", t/1e9 }'
    elif [ "$t" -ge 1000000 ]; then
        awk -v t="$t" 'BEGIN { printf "%.0fM", t/1e6 }'
    elif [ "$t" -ge 1000 ]; then
        awk -v t="$t" 'BEGIN { printf "%.0fK", t/1e3 }'
    else
        printf "%s" "$t"
    fi
}

# Color picker by % thresholds — 256-color, dark variants for light terminal themes.
# green=28 (dark green), olive=130 (dark amber), red=124 (dark red)
color_for_pct() {
    p="$1"
    [ -z "$p" ] && { printf "\033[2m"; return; }
    pi=$(printf '%.0f' "$p")
    if [ "$pi" -ge 80 ]; then
        printf "\033[1;38;5;124m"  # dark red, bold
    elif [ "$pi" -ge 50 ]; then
        printf "\033[1;38;5;130m"  # dark amber/olive, bold
    else
        printf "\033[1;38;5;28m"   # dark green, bold
    fi
}

# --- Assemble ---
# user@host: dark green (22), path: dark blue (25), branch: dark orange (166)
printf "\033[1;38;5;22m%s@%s\033[0m \033[1;38;5;25m%s\033[0m" "$user" "$host" "$short_cwd"

if [ -n "$branch" ]; then
    printf " \033[38;5;166m‹%s›\033[0m" "$branch"
fi

# 5h block segment
if [ -n "$block_pct" ]; then
    pct_str=$(fmt_pct "$block_pct")
    color=$(color_for_pct "$block_pct")
    time_str=$(fmt_time "$block_remaining_min")
    printf " │ 🕐 %s%s%%\033[0m" "$color" "$pct_str"
    [ -n "$time_str" ] && printf " \033[2m(%s left)\033[0m" "$time_str"
fi

# Weekly segment
if [ -n "$weekly_tokens" ] && [ "$weekly_tokens" != "0" ]; then
    tok_str=$(fmt_tokens "$weekly_tokens")
    if [ -n "$CC_WEEKLY_TOKEN_LIMIT" ] && [ "$CC_WEEKLY_TOKEN_LIMIT" -gt 0 ] 2>/dev/null; then
        wpct=$(awk -v t="$weekly_tokens" -v l="$CC_WEEKLY_TOKEN_LIMIT" 'BEGIN { printf "%.0f", (t/l)*100 }')
        wcolor=$(color_for_pct "$wpct")
        printf " │ 📅 %s%s%%\033[0m \033[2m(%s)\033[0m" "$wcolor" "$wpct" "$tok_str"
    else
        printf " │ 📅 \033[2m%s tok\033[0m" "$tok_str"
    fi
fi
