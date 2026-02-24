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

# Modify Config File to Activate BGP
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

# Enable IPv4 Forwarding in FRR
sudo sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# Restart FRR to apply updates
sudo systemctl restart frr

#--------------------------------------------------------------------------
#|                           STEP 2: Configure BGP                        |
#--------------------------------------------------------------------------


#------------------------------------------------------------------------------
# BGP Configuration Values (replace before running):
#   [AS-Number]    - Your local AS number (e.g., 1001)
#   [RID]          - Unique router ID in IP format (e.g., 1.1.1.1)
#   [port]         - Peering interface (e.g., ens5)
#   [remote-as as-number]    - Remote peer's AS number (e.g., 1002)
#   [subnet]/[subnet mask] - Network to advertise (e.g., 10.32.125.0/24)
#------------------------------------------------------------------------------

sudo vtysh << 'EOF'
configure terminal
...
EOF
sudo vtysh << 'EOF'
configure terminal
route-map ALLOW permit 10
exit
router bgp [AS-Number] 
bgp router-id [RID i.e 1.1.1.1]
neighbor [port] interface remote-as [as-number]
address-family ipv4 unicast
network [subnet]/[subnet mask]
neighbor [port] next-hop-self
neighbor [port] route-map ALLOW in
neighbor [port] route-map ALLOW out
exit-address-family
end
write memory
EOF


