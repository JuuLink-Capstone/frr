#!/bin/bash
#------------------------------------------------------------------------
#|                           STEP 1: Install FRR                        |
#------------------------------------------------------------------------

#Install Curl
sudo apt install curl

# Add GPG Keys
curl -s https://deb.frrouting.org/frr/keys.gpg | sudo tee /usr/share/keyrings/frrouting.gpg > /dev/null

# Install FRR
echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-stable" | sudo tee /etc/apt/sources.list.d/frr.list
sudo apt update && sudo apt install frr frr-pythontools

# Modify Config File to Activate BGP and BFD
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo sed -i 's/bfdd=no/bfdd=yes/' /etc/frr/daemons

# Enable IPv4 Forwarding in FRR
sudo sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# Restart FRR to apply updates
sudo systemctl restart frr

#--------------------------------------------------------------------------
#|                     STEP 2: Configure NAT (Masquerade)                 |
#--------------------------------------------------------------------------

# Install iptables persistent so we can modify iptables config file
sudo apt install iptables-persistent

# Apply masquerade rule for internet-facing interface
sudo iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE

# Save changes to config file
sudo netfilter-persistent save

#--------------------------------------------------------------------------
#|                        STEP 3: Configure BGP + BFD                    |
#--------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Configuration Values (replace before running):
#   [AS-Number]        - Your local AS number (e.g., 1001)
#   [RID]              - Unique router ID in IP format (e.g., 1.1.1.1)
#   [port]             - Peering interface (e.g., ens5)
#   [remote-as]        - Remote peer's AS number (e.g., 1002)
#   [subnet]/[mask]    - Network to advertise (e.g., 10.32.125.0/24)
#   [peer-ip]          - BGP neighbor's IP on the peering link (e.g., 10.32.124.2)
#------------------------------------------------------------------------------

sudo vtysh << 'EOF'
configure terminal
route-map ALLOW permit 10
exit
bfd
  peer [peer-ip] 
    no shutdown
  exit
exit
router bgp [AS-Number]
  bgp router-id [RID]
  no bgp network import-check
  neighbor [port] interface remote-as [remote-as]
  address-family ipv4 unicast
    network [subnet]/[mask]
    redistribute kernel
    neighbor [port] next-hop-self
    neighbor [port] route-map ALLOW in
    neighbor [port] route-map ALLOW out
    neighbor [port] bfd
  exit-address-family
end
write memory
EOF