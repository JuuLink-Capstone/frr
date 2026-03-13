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

# Set interfaces in s2-failover.sh
sed -i "s/PRIMARY_IFACE=\"ens4\"/PRIMARY_IFACE=\"$PRIMARY_IFACE\"/" /usr/local/bin/s2-failover.sh
sed -i "s/BACKUP_IFACE=\"ens5\"/BACKUP_IFACE=\"$BACKUP_IFACE\"/" /usr/local/bin/s2-failover.sh

# Set thresholds in s2-check-starlink.sh
sed -i "s/LOSS_THRESHOLD=5/LOSS_THRESHOLD=$LOSS_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh
sed -i "s/LATENCY_THRESHOLD=150/LATENCY_THRESHOLD=$LATENCY_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh
sed -i "s/JITTER_THRESHOLD=30/JITTER_THRESHOLD=$JITTER_THRESHOLD/" /usr/local/bin/s2-check-starlink.sh

chmod +x /usr/local/bin/s2-check-starlink.sh
chmod +x /usr/local/bin/s2-failover.sh
chmod +x /usr/local/bin/s2-route-decision-loop.sh

# Create systemd service
cat > /etc/systemd/system/wan-failover.service << EOF
[Unit]
Description=Dual-WAN Failover Decision Loop
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/s2-route-decision-loop.sh $PRIMARY_IFACE $BACKUP_IFACE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wan-failover

# Step 4: Configure Keepalived
echo "[4/4] Configuring Keepalived..."
cat > /etc/keepalived/keepalived.conf << EOF
vrrp_script check_primary {
    script "/usr/local/bin/s2-check-starlink.sh $PRIMARY_IFACE /tmp/starlink1_score"
    interval 5
    fall 3
    rise 5
}

vrrp_script check_backup {
    script "/usr/local/bin/s2-check-starlink.sh $BACKUP_IFACE /tmp/starlink2_score"
    interval 5
    fall 3
    rise 5
}
EOF

systemctl enable keepalived
systemctl restart keepalived

echo "========================================="
echo " Installation Complete"
echo "========================================="
echo " Primary WAN:  $PRIMARY_IFACE"
echo " Backup WAN:   $BACKUP_IFACE"
echo ""
echo " Services:"
echo " WAN Failover: $(systemctl is-active wan-failover)"
echo " Keepalived:   $(systemctl is-active keepalived)"
echo ""
echo " Check logs:"
echo " journalctl -t failover -f"
echo " journalctl -t starlink-check-$PRIMARY_IFACE -f"
echo " journalctl -t starlink-check-$BACKUP_IFACE -f"
echo "========================================="