#!/bin/bash
# /usr/local/bin/s2-failover.sh
# Usage: PRIMARY_IFACE=ens3 BACKUP_IFACE=ens4 s2-failover.sh

PRIMARY_IFACE="${PRIMARY_IFACE:-ens4}"
BACKUP_IFACE="${BACKUP_IFACE:-ens5}"
SCORE1_FILE="/tmp/starlink1_score"
SCORE2_FILE="/tmp/starlink2_score"
STATE_FILE="/tmp/failover_state"
COUNTER_FILE="/tmp/failover_counter"
LOG_TAG="failover"

FAILOVER_THRESHOLD=3
RECOVERY_THRESHOLD=2
DEAD_BAND=2.0
FAILOVER_RATIO=1.5
RECOVERY_RATIO=1.2

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

# Determine best link (with ratio-based switching)
SCORE_DIFF=$(echo "$SCORE1 - $SCORE2" | bc -l)
SCORE_DIFF_ABS=$(echo "if ($SCORE_DIFF < 0) -($SCORE_DIFF) else $SCORE_DIFF" | bc -l)

if (( $(echo "$SCORE_DIFF_ABS < $DEAD_BAND" | bc -l) )); then
    # Scores are too similar, stick with current
    BEST="$CURRENT"
elif [ "$CURRENT" = "primary" ] && (( $(echo "$SCORE2 < $SCORE1" | bc -l) )); then
    # Only switch FROM primary if backup is significantly better
    FAILOVER_SCORE=$(echo "$SCORE1 * $FAILOVER_RATIO" | bc -l)
    if (( $(echo "$SCORE2 < $FAILOVER_SCORE" | bc -l) )); then
        BEST="backup"
    else
        BEST="primary"
    fi
elif [ "$CURRENT" = "backup" ] && (( $(echo "$SCORE1 < $SCORE2" | bc -l) )); then
    # Only switch back to primary if it's significantly better
    RECOVERY_SCORE=$(echo "$SCORE2 * $RECOVERY_RATIO" | bc -l)
    if (( $(echo "$SCORE1 < $RECOVERY_SCORE" | bc -l) )); then
        BEST="primary"
    else
        BEST="backup"
    fi
else
    # Default logic
    if (( $(echo "$SCORE1 <= $SCORE2" | bc -l) )); then
        BEST="primary"
    else
        BEST="backup"
    fi
fi

# No change needed
if [ "$BEST" = "$CURRENT" ]; then
    echo "0" > "$COUNTER_FILE"
    exit 0
fi

# Increment counter
((COUNTER++))
echo "$COUNTER" > "$COUNTER_FILE"

# Determine threshold (how many consecutive good reads before switching)
if [ "$CURRENT" = "primary" ] && [ "$BEST" = "backup" ]; then
    REQUIRED=$FAILOVER_THRESHOLD
elif [ "$CURRENT" = "backup" ] && [ "$BEST" = "primary" ]; then
    REQUIRED=$RECOVERY_THRESHOLD
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
else
    logger -t "$LOG_TAG" "Switching to BACKUP (SL1=$SCORE1 vs SL2=$SCORE2)"
    ip route replace default via $BACKUP_GW dev $BACKUP_IFACE
fi

echo "$BEST" > "$STATE_FILE"
echo "0" > "$COUNTER_FILE"