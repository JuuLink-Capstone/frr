#!/bin/bash
# /usr/local/bin/score-server.sh
# Serves health score over the direct link on port 8080
# SLU1: bind to 10.32.124.1
# SLU2: bind to 10.32.124.2

BIND_IP="10.32.124.1"   # Change to 10.32.124.2 on SLU2
PORT=8080
SCORE_FILE="/tmp/starlink_score"

while true; do
    SCORE=$(cat "$SCORE_FILE" 2>/dev/null || echo "9999")
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$SCORE" | \
        nc -l -p "$PORT" -s "$BIND_IP" -q 1 2>/dev/null
done