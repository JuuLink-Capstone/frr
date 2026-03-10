#!/bin/bash
# slu_frr_config.sh
# Interactive Starlink BGP Failover Installer
# Installs FRR, NAT, BGP/BFD, SLA monitoring, and Keepalived

if [ "$EUID" -ne 0 ]; then
    echo "Escalating privileges with sudo..."
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo " Starlink BGP Failover Configuration"
echo "========================================="
echo ""

#--------------------------------------------------------------------------
#|                     Configuration Prompts                               |
#--------------------------------------------------------------------------

# Role
read -p "Is this router the PRIMARY (master) or BACKUP? [primary/backup]: " ROLE_INPUT
if [ "$ROLE_INPUT" = "primary" ]; then
    KA_STATE="MASTER"
    KA_PRIORITY="150"
elif [ "$ROLE_INPUT" = "backup" ]; then
    KA_STATE="BACKUP"
    KA_PRIORITY="100"
else
    echo "Invalid role. Use 'primary' or 'backup'."
    exit 1
fi

# BGP
read -p "Local AS number (e.g. 1001): " AS_NUMBER
read -p "Router ID (e.g. 1.1.1.1): " RID
read -p "Remote peer AS number (e.g. 1002): " REMOTE_AS
read -p "LAN subnet to advertise (e.g. 10.32.125.0/24): " LAN_SUBNET

# Interfaces
read -p "Starlink interface (e.g. ens4): " STARLINK_INTERFACE
read -p "Direct port interface to peer router (e.g. ens5): " DIRECT_LINK_INTERFACE

# IPs on the direct link
read -p "This router's IP on direct link (e.g. 10.32.124.1): " BIND_IP
read -p "Peer router's IP on direct link (e.g. 10.32.124.2): " PEER_IP
PEER_BGP_IP="$PEER_IP"

# SLA Thresholds
read -p "Packet loss threshold % (default 5): " LOSS_INPUT
LOSS_THRESHOLD=${LOSS_INPUT:-5}
read -p "Latency threshold ms (default 150): " LATENCY_INPUT
LATENCY_THRESHOLD=${LATENCY_INPUT:-150}
read -p "Jitter threshold ms (default 50): " JITTER_INPUT
JITTER_THRESHOLD=${JITTER_INPUT:-50}

# Confirm
echo ""
echo "========================================="
echo " Configuration Summary"
echo "========================================="
echo " Role:              $KA_STATE (priority $KA_PRIORITY)"
echo " Local AS:          $AS_NUMBER"
echo " Router ID:         $RID"
echo " Remote AS:         $REMOTE_AS"
echo " LAN Subnet:        $LAN_SUBNET"
echo " Starlink Iface:    $STARLINK_INTERFACE"
echo " Direct Link Iface: $DIRECT_LINK_INTERFACE"
echo " This Router IP:    $BIND_IP"
echo " Peer Router IP:    $PEER_IP"
echo " Loss Threshold:    ${LOSS_THRESHOLD}%"
echo " Latency Threshold: ${LATENCY_THRESHOLD}ms"
echo " Jitter Threshold:  ${JITTER_THRESHOLD}ms"
echo "========================================="
echo ""
read -p "Proceed with installation? [y/n]: " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

#------------------------------------------------------------------------
#|                        STEP 1: Install FRR                           |
#------------------------------------------------------------------------
echo ""
echo "[1/5] Installing FRR..."

apt update
apt install curl fping bc -y

curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-stable" | tee /etc/apt/sources.list.d/frr.list
apt update && apt install frr frr-pythontools -y

# Enable BGP and BFD daemons
sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sed -i 's/bfdd=no/bfdd=yes/' /etc/frr/daemons

# Enable IPv4 forwarding
sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

systemctl restart frr

echo "FRR installed and running."

#--------------------------------------------------------------------------
#|                  STEP 2: Configure NAT (Masquerade)                    |
#--------------------------------------------------------------------------
echo ""
echo "[2/5] Configuring NAT on $STARLINK_INTERFACE..."

DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y

iptables -t nat -A POSTROUTING -o "$STARLINK_INTERFACE" -j MASQUERADE
netfilter-persistent save

echo "NAT masquerade configured on $STARLINK_INTERFACE."

#--------------------------------------------------------------------------
#|                     STEP 3: Configure BGP + BFD                        |
#--------------------------------------------------------------------------
echo ""
echo "[3/5] Configuring BGP + BFD (AS $AS_NUMBER, RID $RID)..."

systemctl stop frr

# Remove any existing capability link-local lines (both positive and negative)
sed -i '/capability link-local/d' /etc/frr/frr.conf

# Add the correct line after "neighbor ens5 bfd"
sed -i '/neighbor ens5 bfd/a \ neighbor ens5 capability link-local' /etc/frr/frr.conf
systemctl start frr

vtysh << EOF
configure terminal
route-map ALLOW permit 10
exit
bfd
  peer $PEER_BGP_IP
    no shutdown
  exit
exit
router bgp $AS_NUMBER
  bgp router-id $RID
  no bgp network import-check
  neighbor $DIRECT_LINK_INTERFACE interface remote-as $REMOTE_AS
  address-family ipv4 unicast
    network $LAN_SUBNET
    redistribute kernel
    neighbor $DIRECT_LINK_INTERFACE next-hop-self
    neighbor $DIRECT_LINK_INTERFACE route-map ALLOW in
    neighbor $DIRECT_LINK_INTERFACE route-map ALLOW out
    neighbor $DIRECT_LINK_INTERFACE bfd
  exit-address-family
end
write memory
EOF

echo "BGP + BFD configured."

#--------------------------------------------------------------------------
#|                   STEP 4: Install SLA Monitoring Scripts                |
#--------------------------------------------------------------------------
echo ""
echo "[4/5] Installing SLA monitoring scripts..."

# Copy scripts to system path
cp "$SCRIPT_DIR/check-starlink.sh" /usr/local/bin/
cp "$SCRIPT_DIR/score-server.sh" /usr/local/bin/
cp "$SCRIPT_DIR/failover.sh" /usr/local/bin/
cp "$SCRIPT_DIR/route-decision-loop.sh" /usr/local/bin/

# Set correct IPs for this router
sed -i "s/BIND_IP=\".*\"/BIND_IP=\"$BIND_IP\"/" /usr/local/bin/score-server.sh
sed -i "s/PEER_IP=\".*\"/PEER_IP=\"$PEER_IP\"/" /usr/local/bin/failover.sh

# Set correct interface and thresholds for health check
sed -i "s/-I ens4/-I $STARLINK_INTERFACE/" /usr/local/bin/check-starlink.sh
sed -i "s/LOSS_THRESHOLD=.*/LOSS_THRESHOLD=$LOSS_THRESHOLD/" /usr/local/bin/check-starlink.sh
sed -i "s/LATENCY_THRESHOLD=.*/LATENCY_THRESHOLD=$LATENCY_THRESHOLD/" /usr/local/bin/check-starlink.sh
sed -i "s/JITTER_THRESHOLD=.*/JITTER_THRESHOLD=$JITTER_THRESHOLD/" /usr/local/bin/check-starlink.sh

# Make executable
chmod +x /usr/local/bin/check-starlink.sh
chmod +x /usr/local/bin/score-server.sh
chmod +x /usr/local/bin/failover.sh
chmod +x /usr/local/bin/route-decision-loop.sh

# Create systemd service for score server
cat > /etc/systemd/system/starlink-score.service << 'SVCEOF'
[Unit]
Description=Starlink Health Score Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/score-server.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# Create systemd service for decision loop
cat > /etc/systemd/system/starlink-decision.service << 'SVCEOF'
[Unit]
Description=Starlink Route Decision Loop
After=network-online.target frr.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/route-decision-loop.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now starlink-score
systemctl enable --now starlink-decision

echo "SLA scripts installed (bind=$BIND_IP, peer=$PEER_IP)."

#--------------------------------------------------------------------------
#|                     STEP 5: Install Keepalived                          |
#--------------------------------------------------------------------------
echo ""
echo "[5/5] Installing Keepalived..."

apt install keepalived -y

cat > /etc/keepalived/keepalived.conf << EOF
vrrp_script check_starlink {
    script "/usr/local/bin/check-starlink.sh"
    interval 5
    weight -50
    fall 3
    rise 5
}

vrrp_instance STARLINK_FAILOVER {
    state $KA_STATE
    interface $DIRECT_LINK_INTERFACE
    virtual_router_id 51
    priority $KA_PRIORITY
    advert_int 1

    unicast_src_ip $BIND_IP
    unicast_peer {
        $PEER_IP
    }

    track_script {
        check_starlink
    }

    notify_master "/usr/local/bin/failover.sh master"
    notify_backup "/usr/local/bin/failover.sh backup"
}
EOF

systemctl enable keepalived
systemctl restart keepalived

echo "Keepalived installed ($KA_STATE, priority $KA_PRIORITY)."

#--------------------------------------------------------------------------
#|                          INSTALLATION COMPLETE                          |
#--------------------------------------------------------------------------
echo ""
echo "========================================="
echo " Installation Complete"
echo "========================================="
echo ""
echo " Role:       $KA_STATE (priority $KA_PRIORITY)"
echo " BGP AS:     $AS_NUMBER (RID: $RID)"
echo " Peer AS:    $REMOTE_AS (IP: $PEER_IP)"
echo " Starlink:   $STARLINK_INTERFACE"
echo " Direct:     $DIRECT_LINK_INTERFACE"
echo " SLA:        Loss>${LOSS_THRESHOLD}% RTT>${LATENCY_THRESHOLD}ms Jitter>${JITTER_THRESHOLD}ms"
echo ""
echo " FRR:        $(systemctl is-active frr)"
echo " Keepalived: $(systemctl is-active keepalived)"
echo " Score Srv:  $(systemctl is-active starlink-score)"
echo " Decision:   $(systemctl is-active starlink-decision)"
echo ""
echo " Verify BGP: sudo vtysh -c 'show ip bgp summary'"
echo " Check logs: journalctl -t starlink-check -f"
echo "             journalctl -t failover -f"
echo "========================================="