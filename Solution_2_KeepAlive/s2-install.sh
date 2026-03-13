#!/bin/bash
# install.sh
# Single-router dual-WAN failover installer

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo " Dual-WAN Failover Installer"
echo "========================================="

# Interfaces
read -p "Primary WAN interface (e.g. ens4): " PRIMARY_IFACE
read -p "Backup WAN interface (e.g. ens5): " BACKUP_IFACE

# SLA Thresholds
read -p "Packet loss threshold % (default 5): " LOSS_INPUT
LOSS_THRESHOLD=${LOSS_INPUT:-5}
read -p "Latency threshold ms (default 150): " LATENCY_INPUT
LATENCY_THRESHOLD=${LATENCY_INPUT:-150}
read -p "Jitter threshold ms (default 30): " JITTER_INPUT
JITTER_THRESHOLD=${JITTER_INPUT:-30}

echo ""
echo "========================================="
echo " Configuration Summary"
echo "========================================="
echo " Primary WAN:  $PRIMARY_IFACE"
echo " Backup WAN:   $BACKUP_IFACE"
echo " Loss:         ${LOSS_THRESHOLD}%"
echo " Latency:      ${LATENCY_THRESHOLD}ms"
echo " Jitter:       ${JITTER_THRESHOLD}ms"
echo "========================================="
read -p "Proceed? [y/n]: " CONFIRM
if [ "$CONFIRM" != "y" ]; then exit 0; fi

# Step 1: Install packages
echo "[1/4] Installing packages..."
apt update
apt install -y fping bc iptables-persistent keepalived
ubuntu-24.04.3-desktop-amd64.iso
# Enable IP forwarding
sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Step 2: Configure NAT
echo "[2/4] Configuring NAT..."
iptables -t nat -F POSTROUTING
iptables -t nat -A POSTROUTING -o $PRIMARY_IFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -o $BACKUP_IFACE -j MASQUERADE
netfilter-persistent save

# Step 3: Install scripts
echo "[3/4] Installing scripts..."
cp "$SCRIPT_DIR/s2-check-starlink.sh" /usr/local/bin/
cp "$SCRIPT_DIR/s2-failover.sh" /usr/local/bin/
cp "$SCRIPT_DIR/s2-route-decision-loop.sh" /usr/local/bin/

# Set interfaces in failover.sh
sed -i "s/PRIMARY_IFACE=\"ens4\"/PRIMARY_IFACE=\"$PRIMARY_IFACE\"/" /usr/local/bin/s2-failover.sh
sed -i "s/BACKUP_IFACE=\"ens5\"/BACKUP_IFACE=\"$BACKUP_IFACE\"/" /usr/local/bin/s2-failover.sh

# Set thresholds in check-starlink.sh
sed -i "s/LOSS_THRESHOLD=5/LOSS_THRESHOLD=$LOSS_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh
sed -i "s/LATENCY_THRESHOLD=150/LATENCY_THRESHOLD=$LATENCY_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh
sed -i "s/JITTER_THRESHOLD=30/JITTER_THRESHOLD=$JITTER_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh

# Set interfaces in route-decision-loop.sh
sed -i "s/ens4/$PRIMARY_IFACE/g" /usr/local/bin/s2-route-decision-loop.sh
sed -i "s/ens5/$BACKUP_IFACE/g" /usr/local/bin/s2-route-decision-loop.sh

chmod +x /usr/local/bin/s2-check-starlink.sh
chmod +x /usr/local/bin/s2-failover.sh
chmod +x /usr/local/bin/s2-route-decision-loop.sh

# Create systemd service
cat > /etc/systemd/system/wan-failover.service << 'EOF'
[Unit]
Description=Dual-WAN Failover Decision Loop
After=network-online.target
Wants=network-online.target

[Service]
Type=simple