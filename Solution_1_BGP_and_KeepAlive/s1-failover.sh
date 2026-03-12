#!/bin/bash
# /usr/local/bin/failover.sh
# Compares local score vs peer score and adjusts BGP local-preference
# Run via Keepalived notify or the decision loop

PEER_IP="10.32.124.2"       # Change to 10.32.124.1 on SLU2
PEER_PORT=8080
SCORE_FILE="/tmp/starlink_score"
STATE_FILE="/tmp/failover_state"
COUNTER_FILE="/tmp/failover_counter"
HOLD_FILE="/tmp/failover_hold"
LOG_TAG="failover"

# Hysteresis settings
FAILOVER_THRESHOLD=3    # consecutive cycles before failing over
RECOVERY_THRESHOLD=5    # consecutive cycles before recovering
HOLD_TIMER=120          # seconds to hold after failover before allowing revert

# Initialize local-preference on first run
if [ ! -f "$STATE_FILE" ]; then
    ROLE=$(cat "/etc/frr/router_role" 2>/dev/null || echo "backup")
    if [ "$ROLE" = "primary" ]; then
        logger -t "$LOG_TAG" "Initializing as PRIMARY — setting local-preference 200"
        vtysh -c "conf t" \
              -c "route-map ALLOW permit 10" \
              -c "set local-preference 200" \
              -c "end" -c "write memory"
    else
        logger -t "$LOG_TAG" "Initializing as BACKUP — setting local-preference 100"
        vtysh -c "conf t" \
              -c "route-map ALLOW permit 10" \
              -c "set local-preference 100" \
              -c "end" -c "write memory"
    fi
    echo "local" > "$STATE_FILE"
    echo "0" > "$COUNTER_FILE"
fi

MY_SCORE=$(cat "$SCORE_FILE" 2>/dev/null || echo "9999")
PEER_SCORE=$(curl -s --connect-timeout 3 "http://${PEER_IP}:${PEER_PORT}" || echo "9999")

CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "local")
COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

logger -t "$LOG_TAG" "My=$MY_SCORE Peer=$PEER_SCORE Current=$CURRENT Counter=$COUNTER"

# Determine which link is better (lower score = better)
if (( $(echo "$MY_SCORE <= $PEER_SCORE" | bc -l) )); then
    BEST="local"
else
    BEST="peer"
fi

# If no change needed, reset counter
if [ "$BEST" = "$CURRENT" ]; then
    echo "0" > "$COUNTER_FILE"
    exit 0
fi

# Change needed — increment counter for hysteresis
((COUNTER++))
echo "$COUNTER" > "$COUNTER_FILE"

# Determine required threshold based on direction
if [ "$CURRENT" = "local" ] && [ "$BEST" = "peer" ]; then
    REQUIRED=$FAILOVER_THRESHOLD
elif [ "$CURRENT" = "peer" ] && [ "$BEST" = "local" ]; then
    REQUIRED=$RECOVERY_THRESHOLD

    # Check hold timer — don't revert too quickly
    if [ -f "$HOLD_FILE" ]; then
        HOLD_START=$(cat "$HOLD_FILE")
        NOW=$(date +%s)
        ELAPSED=$((NOW - HOLD_START))
        if (( ELAPSED < HOLD_TIMER )); then
            logger -t "$LOG_TAG" "Hold timer active (${ELAPSED}s / ${HOLD_TIMER}s) — not reverting yet"
            exit 0
        fi
    fi
else
    REQUIRED=$FAILOVER_THRESHOLD
fi

# Haven't hit threshold yet — wait
if (( COUNTER < REQUIRED )); then
    logger -t "$LOG_TAG" "Threshold not met ($COUNTER / $REQUIRED) — holding"
    exit 0
fi

# Threshold met — execute state change
if [ "$BEST" = "local" ]; then
    ROLE=$(cat "/etc/frr/router_role" 2>/dev/null || echo "backup")
    if [ "$ROLE" = "primary" ]; then
        RECOVER_LOCPREF=200
    else
        RECOVER_LOCPREF=100
    fi
    logger -t "$LOG_TAG" "LOCAL is better ($MY_SCORE vs $PEER_SCORE) — taking MASTER (local-pref $RECOVER_LOCPREF)"
    vtysh -c "conf t" \
          -c "route-map ALLOW permit 10" \
          -c "set local-preference $RECOVER_LOCPREF" \
          -c "end" -c "write memory"
else
    logger -t "$LOG_TAG" "PEER is better ($MY_SCORE vs $PEER_SCORE) — becoming BACKUP"
    vtysh -c "conf t" \
          -c "route-map ALLOW permit 10" \
          -c "set local-preference 50" \
          -c "end" -c "write memory"
    # Start hold timer
    date +%s > "$HOLD_FILE"
fi

echo "$BEST" > "$STATE_FILE"
echo "0" > "$COUNTER_FILE"