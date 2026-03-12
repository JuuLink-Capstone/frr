#!/bin/bash
# /usr/local/bin/route-decision-loop.sh
# Continuous loop that runs the failover decision every 10 seconds

while true; do
    /usr/local/bin/failover.sh
    sleep 10
done