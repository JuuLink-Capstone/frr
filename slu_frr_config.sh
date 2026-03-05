#!/bin/bash
# slu_frr_config.sh
# Master installation script for Starlink BGP failover
# Usage: sudo ./slu_frr_config.sh [slu1|slu2]

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./slu_frr_config.sh [slu1|slu2]"
    exit 1
fi

ROLE=${1:-slu1}

if [ "$ROLE" = "slu1" ]; then
    AS_NUMBER="1001"
    RID="1.1.1.1"
    REMOTE_AS="1002"
    LAN_SUBNET="10.32.125.0/24"
    PEER_BGP_IP="10.32.124.2"
    BIND_IP="10.32.124.1"
    PEER_IP="10.32.124.2"
    KA_STATE="MASTER"
    KA_PRIORITY="150"
    SLU_Port_Interface="ens4"
elif [ "$ROLE" = "slu2" ]; then
    AS_NUMBER="1002"
    RID="2.2.2.2"
    REMOTE_AS="1001"
    LAN_SUBNET="10.32.126.0/24"
    PEER_BGP_IP="10.32.124.1"
    BIND_IP="10.32.124.2"
    PEER_IP="10.32.124.1"
    KA_STATE="BACKUP"
    KA_PRIORITY="100"
    SLU_PORT_INTERFACE="ens4"
else
    echo "Usage: sudo ./slu_frr_config.sh [slu1|slu2]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo " FRR Install for $ROLE"
echo "========================================="

#------------------------------------------------------------------------
#|                        STEP 1: Install FRR                           |
#------------------------------------------------------------------------
echo ""
echo "[1/5] Installing FRR..."

apt install curl fping bc -y

curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-stable" | tee /etc/apt/sources.list.d/frr.list
apt update && apt install frr frr-pythontools -y

sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sed -i 's/bfdd=no/bfdd=yes/' /etc/frr/daemons

sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

systemctl restart frr

echo "FRR installed and running."

#--------------------------------------------------------------------------
#|                  STEP 2: Configure NAT (Masquerade)                    |
#--------------------------------------------------------------------------
echo ""
echo "[2/5] Configuring NAT..."

DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y

iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE
netfilter-persistent save

echo "NAT masquerade configured on ens4."

#--------------------------------------------------------------------------
#|                     STEP 3: Configure BGP + BFD                        |
#--------------------------------------------------------------------------
echo ""
echo "[3/5] Configuring BGP + BFD as $ROLE (AS $AS_NUMBER)..."

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
  neighbor ens5 interface remote-as $REMOTE_AS
  address-family ipv4 unicast
    network $LAN_SUBNET
    redistribute kernel
    neighbor ens5 next-hop-self
    neighbor ens5 route-map ALLOW in
    neighbor ens5 route-map ALLOW out
    neighbor ens5 bfd
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

# Set correct ports for scripts
sed -i "s/-I ens4/-I $SLU_PORT_INTERFACE/" /usr/local/bin/check-starlink.sh

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
    interface ens5
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
echo " Installation complete: $ROLE"
echo "========================================="
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
```

Now your repo just needs:
```
FRR/
├── slu_frr_config.sh          # Run this — does everything
├── check-starlink.sh          # Copied to /usr/local/bin/ by the script
├── score-server.sh            # Copied to /usr/local/bin/ by the script
├── failover.sh                # Copied to /usr/local/bin/ by the script
├── route-decision-loop.sh     # Copied to /usr/local/bin/ by the script
└── README.md