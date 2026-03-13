#!/bin/bash
# /usr/local/bin/s2-route-decision-loop.sh
# Usage: s2-route-decision-loop.sh [PRIMARY_IFACE] [BACKUP_IFACE]

PRIMARY_IFACE="${1:-ens4}"
BACKUP_IFACE="${2:-ens5}"

while true; do
    /usr/local/bin/s2-check-starlink.sh "$PRIMARY_IFACE" /tmp/starlink1_score
    /usr/local/bin/s2-check-starlink.sh "$BACKUP_IFACE" /tmp/starlink2_score
    /usr/local/bin/s2-failover.sh
    sleep 10
done