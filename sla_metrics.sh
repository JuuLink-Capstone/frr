#!/bin/bash
# /usr/local/bin/check-starlink.sh
# Returns exit 0 (healthy) or exit 1 (degraded) based on SLA metrics

TARGETS=("1.1.1.1" "8.8.8.8")
LOSS_THRESHOLD=10       # percent
LATENCY_THRESHOLD=150   # ms
JITTER_THRESHOLD=50     # ms
SCORE_FILE="/tmp/starlink_score"

TOTAL_LOSS=0
TOTAL_RTT=0
TOTAL_JITTER=0
COUNT=0

for TARGET in "${TARGETS[@]}"; do
    # Send 10 pings, 200ms apart
    RESULT=$(fping -C 10 -q -p 200 "$TARGET" 2>&1 | tail -1)

    # Extract RTT values (excluding losses marked as '-')
    RTTS=$(echo "$RESULT" | grep -oP '[\d.]+' | tail -n +2)
    LOST=$(echo "$RESULT" | tr ' ' '\n' | grep -c '^\-$')

    LOSS_PCT=$(( LOST * 100 / 10 ))

    if [ -n "$RTTS" ]; then
        AVG=$(echo "$RTTS" | awk '{s+=$1;n++} END{if(n>0) print s/n; else print 9999}')
        # Jitter = standard deviation of RTT values
        JITTER=$(echo "$RTTS" | awk '{sum+=$1; sumsq+=$1*$1; n++} END{if(n>1) print sqrt(sumsq/n - (sum/n)^2); else print 0}')
    else
        AVG=9999
        JITTER=9999
    fi

    TOTAL_LOSS=$((TOTAL_LOSS + LOSS_PCT))
    TOTAL_RTT=$(echo "$TOTAL_RTT + $AVG" | bc)
    TOTAL_JITTER=$(echo "$TOTAL_JITTER + $JITTER" | bc)
    ((COUNT++))
done

AVG_LOSS=$((TOTAL_LOSS / COUNT))
AVG_RTT=$(echo "scale=2; $TOTAL_RTT / $COUNT" | bc)
AVG_JITTER=$(echo "scale=2; $TOTAL_JITTER / $COUNT" | bc)

# Weighted score (lower is better)
SCORE=$(echo "scale=2; $AVG_LOSS * 10 + $AVG_RTT + $AVG_JITTER * 2" | bc)

# Save score so the other router can read it
echo "$SCORE" > "$SCORE_FILE"
logger -t starlink-check "Loss=${AVG_LOSS}% RTT=${AVG_RTT}ms Jitter=${AVG_JITTER}ms Score=${SCORE}"

# Determine health
BREACH=0
if (( AVG_LOSS > LOSS_THRESHOLD )); then BREACH=1; fi
if (( $(echo "$AVG_RTT > $LATENCY_THRESHOLD" | bc -l) )); then BREACH=1; fi
if (( $(echo "$AVG_JITTER > $JITTER_THRESHOLD" | bc -l) )); then BREACH=1; fi

exit $BREACH