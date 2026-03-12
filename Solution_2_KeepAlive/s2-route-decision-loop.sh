#!/bin/bash
# /usr/local/bin/route-decision-loop.sh

while true; do
    /usr/local/bin/check-starlink.sh ens4 /tmp/starlink1_score
    /usr/local/bin/check-starlink.sh ens5 /tmp/starlink2_score
    /usr/local/bin/failover.sh
    sleep 10
done