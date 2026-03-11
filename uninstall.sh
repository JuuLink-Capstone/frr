#!/bin/bash
# uninstall.sh
# Removes all Starlink BGP failover components for a fresh install

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

echo "========================================="
echo " Starlink BGP Failover Uninstaller"
echo "========================================="

# Stop and disable services
echo "Stopping services..."
systemctl stop starlink-score starlink-decision keepalived frr
systemctl disable starlink-score starlink-decision keepalived

# Remove systemd services
echo "Removing systemd services..."
rm -f /etc/systemd/system/starlink-score.service
rm -f /etc/systemd/system/starlink-decision.service
systemctl daemon-reload

# Remove scripts
echo "Removing scripts..."
rm -f /usr/local/bin/check-starlink.sh
rm -f /usr/local/bin/score-server.sh
rm -f /usr/local/bin/failover.sh
rm -f /usr/local/bin/route-decision-loop.sh

# Remove temp/state files
echo "Removing state files..."
rm -f /tmp/starlink_score
rm -f /tmp/failover_state
rm -f /tmp/failover_counter
rm -f /tmp/failover_hold

# Remove role file
rm -f /etc/frr/router_role

# Reset FRR config
echo "Resetting FRR..."
rm -f /etc/frr/frr.conf
systemctl start frr

# Flush NAT rules
echo "Flushing NAT rules..."
iptables -t nat -F POSTROUTING
netfilter-persistent save

# Remove keepalived config
echo "Removing keepalived config..."
rm -f /etc/keepalived/keepalived.conf

echo "========================================="
echo " Uninstall complete. Ready for fresh install."
echo "========================================="