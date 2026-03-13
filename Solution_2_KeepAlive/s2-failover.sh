#!/bin/bash
# /usr/local/bin/s2-failover.sh

PRIMARY_IFACE="ens3"
BACKUP_IFACE="ens4"
SCORE1_FILE="/tmp/starlink1_score"
SCORE2_FILE="/tmp/starlink2_score"
STATE_FILE="/tmp/failover_state"
COUNTER_FILE="/tmp/failover_counter"
HOLD_FILE="/tmp/failover_hold"
LOG_TAG="failover"

FAILOVER_THRESHOLD=2
RECOVERY_THRESHOLD=3
HOLD_TIMER=60

# Get gateway IPs dynamically
PRIMARY_GW=$(ip route show dev $PRIMARY_IFACE proto dhcp | awk '/default/ {print $3}')
BACKUP_GW=$(ip route show dev $BACKUP_IFACE proto dhcp | awk '/default/ {print $3}')

# If no DHCP default, try kernel
if [ -z "$PRIMARY_GW" ]; then
    PRIMARY_GW=$(ip route show dev $PRIMARY_IFACE | awk '/default/ {print $3}')
fi
if [ -z "$BACKUP_GW" ]; then
    BACKUP_GW=$(ip route show dev $BACKUP_IFACE | awk '/default/ {print $3}')
fi

logger -t "$LOG_TAG" "PRIMARY_GW=$PRIMARY_GW BACKUP_GW=$BACKUP_GW"

SCORE1=$(cat "$SCORE1_FILE" 2>/dev/null || echo "9999")
SCORE2=$(cat "$SCORE2_FILE" 2>/dev/null || echo "9999")
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "primary")
COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

logger -t "$LOG_TAG" "SL1=$SCORE1 SL2=$SCORE2 Current=$CURRENT Counter=$COUNTER"

# Determine best link
if (( $(echo "$SCORE1 <= $SCORE2" | bc -l) )); then
    BEST="primary"
else
    BEST="backup"
fi

# No change needed
if [ "$BEST" = "$CURRENT" ]; then
    echo "0" > "$COUNTER_FILE"
    exit 0
fi

# Increment counter
((COUNTER++))
echo "$COUNTER" > "$COUNTER_FILE"

# Determine threshold
if [ "$CURRENT" = "primary" ] && [ "$BEST" = "backup" ]; then
    REQUIRED=$FAILOVER_THRESHOLD
elif [ "$CURRENT" = "backup" ] && [ "$BEST" = "primary" ]; then
    REQUIRED=$RECOVERY_THRESHOLD
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

# Haven't hit threshold yet
if (( COUNTER < REQUIRED )); then
    logger -t "$LOG_TAG" "Threshold not met ($COUNTER / $REQUIRED) — holding"
    exit 0
fi

# Execute state change
if [ "$BEST" = "primary" ]; then
    logger -t "$LOG_TAG" "Switching to PRIMARY (SL1=$SCORE1 vs SL2=$SCORE2)"
    ip route replace default via $PRIMARY_GW dev $PRIMARY_IFACE
    date +%s > "$HOLD_FILE"
else
    logger -t "$LOG_TAG" "Switching to BACKUP (SL1=$SCORE1 vs SL2=$SCORE2)"
    ip route replace default via $BACKUP_GW dev $BACKUP_IFACE
    date +%s > "$HOLD_FILE"
fi

echo "$BEST" > "$STATE_FILE"
echo "0" > "$COUNTER_FILE"