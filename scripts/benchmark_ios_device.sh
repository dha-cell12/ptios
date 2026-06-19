#!/bin/sh

DURATION=${1:-60}
INTERVAL=${2:-1}
OUT=${3:-/var/mobile/Library/TLinkauto/benchmark_ios.csv}
PROCS=${4:-"SpringBoard tlinkautod"}

mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
echo "timestamp,process,pid,cpu_percent,rss_kb" > "$OUT"

end=$(( $(date +%s) + DURATION ))

find_pid() {
    name="$1"
    if command -v pidof >/dev/null 2>&1; then
        pidof "$name" 2>/dev/null | awk '{print $1}'
        return
    fi
    ps ax 2>/dev/null | awk -v n="$name" '$0 ~ n && $0 !~ /awk/ {print $1; exit}'
}

sample_ps() {
    pid="$1"
    name="$2"
    ts="$3"
    line="$(ps -p "$pid" -o pid=,pcpu=,rss= 2>/dev/null | head -n 1)"
    if [ -n "$line" ]; then
        set -- $line
        echo "$ts,$name,$1,$2,$3" >> "$OUT"
        return
    fi

    line="$(ps -p "$pid" -o pid=,rss= 2>/dev/null | head -n 1)"
    if [ -n "$line" ]; then
        set -- $line
        echo "$ts,$name,$1,,${2:-}" >> "$OUT"
        return
    fi

    echo "$ts,$name,$pid,," >> "$OUT"
}

echo "benchmark start duration=${DURATION}s interval=${INTERVAL}s output=$OUT"
while [ "$(date +%s)" -le "$end" ]; do
    ts="$(date +%s)"
    for proc in $PROCS; do
        pid="$(find_pid "$proc")"
        if [ -n "$pid" ]; then
            sample_ps "$pid" "$proc" "$ts"
        else
            echo "$ts,$proc,,," >> "$OUT"
        fi
    done
    sleep "$INTERVAL"
done
echo "benchmark done output=$OUT"
