#!/bin/bash

# StrongSwan Two-Tunnel Configuration Script with Interactive Prompts
# Creates two separate tunnels (one per ISP) between SLU1 and SLU2

set -e

echo "=========================================="
echo "StrongSwan Two-Tunnel Configuration"
echo "=========================================="
echo ""

# Prompt for node type
echo "What type of node is this?"
echo "1) SLU1 (Initiator with 2 ISPs)"
echo "2) SLU2 (Responder)"
read -p "Enter choice (1 or 2): " node_choice

if [ "$node_choice" = "1" ]; then
    NODE_TYPE="slu1"
elif [ "$node_choice" = "2" ]; then
    NODE_TYPE="slu2"
else
    echo "Error: Invalid choice. Please enter 1 or 2."
    exit 1
fi

echo ""
read -p "Enter the remote node's IP address (SLU2): " REMOTE_IP
read -sp "Enter the pre-shared key: " PSK
echo ""

if [ -z "$REMOTE_IP" ] || [ -z "$PSK" ]; then
    echo "Error: All fields are required."
    exit 1
fi

# ==================== SLU1 Setup ====================
if [ "$NODE_TYPE" = "slu1" ]; then
    echo ""
    echo "Enter the two local IP addresses (one for each ISP):"
    read -p "ISP1 local IP address: " ISP1_LOCAL
    read -p "ISP2 local IP address: " ISP2_LOCAL
    
    if [ -z "$ISP1_LOCAL" ] || [ -z "$ISP2_LOCAL" ]; then
        echo "Error: All IP addresses are required."
        exit 1
    fi

    echo ""
    echo "=========================================="
    echo "Configuration Summary - SLU1"
    echo "=========================================="
    echo "ISP1 Local IP: $ISP1_LOCAL"
    echo "ISP2 Local IP: $ISP2_LOCAL"
    echo "Remote IP (SLU2): $REMOTE_IP"
    echo "Pre-shared Key: ****"
    echo ""

    read -p "Proceed with configuration? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    echo "Setting up StrongSwan for SLU1 node with three tunnels..."

    # Create config directory
    sudo mkdir -p /etc/swanctl/conf.d

    echo "Creating tunnels.conf for SLU1..."
    
    sudo tee /etc/swanctl/conf.d/tunnels.conf > /dev/null <<EOF
connections {
  tunnel-isp1 {
    local_addrs = $ISP1_LOCAL
    remote_addrs = $REMOTE_IP
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel-isp1 {
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0
        esp_proposals = aes128-sha256
        mode = tunnel
        rekey_time = 3600s
      }
    }
    
    version = 2
    proposals = aes128-sha256-modp2048
    rekey_time = 28800s
  }

  tunnel-isp2 {
    local_addrs = $ISP2_LOCAL
    remote_addrs = $REMOTE_IP
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel-isp2 {
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0
        esp_proposals = aes128-sha256
        mode = tunnel
        rekey_time = 3600s
      }
    }
    
    version = 2
    proposals = aes128-sha256-modp2048
    rekey_time = 28800s
  }
}

secrets {
  ike-isp1 {
    id = $ISP1_LOCAL
    secret = "$PSK"
  }
  ike-isp2 {
    id = $ISP2_LOCAL
    secret = "$PSK"
  }
}
EOF

    echo "Creating slu2.conf for remote identity..."
    
    sudo tee /etc/swanctl/conf.d/slu2.conf > /dev/null <<EOF
secrets {
  ike-slu2 {
    id = $REMOTE_IP
    secret = "$PSK"
  }
}
EOF

# ==================== SLU2 Setup ====================
elif [ "$NODE_TYPE" = "slu2" ]; then
    echo ""
    echo "Enter the two remote IP addresses (SLU1's ISP IPs):"
    read -p "ISP1 remote IP address: " ISP1_REMOTE
    read -p "ISP2 remote IP address: " ISP2_REMOTE
    
    if [ -z "$ISP1_REMOTE" ] || [ -z "$ISP2_REMOTE" ]; then
        echo "Error: All IP addresses are required."
        exit 1
    fi

    read -p "Enter this node's (SLU2) local IP address: " LOCAL_IP
    
    if [ -z "$LOCAL_IP" ]; then
        echo "Error: Local IP is required."
        exit 1
    fi

    echo ""
    echo "=========================================="
    echo "Configuration Summary - SLU2"
    echo "=========================================="
    echo "Local IP (SLU2): $LOCAL_IP"
    echo "ISP1 Remote IP (SLU1): $ISP1_REMOTE"
    echo "ISP2 Remote IP (SLU1): $ISP2_REMOTE"
    echo "Pre-shared Key: ****"
    echo ""

    read -p "Proceed with configuration? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    echo "Setting up StrongSwan for SLU2 node with three tunnels..."

    # Create config directory
    sudo mkdir -p /etc/swanctl/conf.d

    echo "Creating tunnels.conf for SLU2..."
    
    sudo tee /etc/swanctl/conf.d/tunnels.conf > /dev/null <<EOF
connections {
  tunnel-from-isp1 {
    local_addrs = $LOCAL_IP
    remote_addrs = $ISP1_REMOTE
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel-isp1 {
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0
        esp_proposals = aes128-sha256
        mode = tunnel
        rekey_time = 3600s
      }
    }
    
    version = 2
    proposals = aes128-sha256-modp2048
    rekey_time = 28800s
  }

  tunnel-from-isp2 {
    local_addrs = $LOCAL_IP
    remote_addrs = $ISP2_REMOTE
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel-isp2 {
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0
        esp_proposals = aes128-sha256
        mode = tunnel
        rekey_time = 3600s
      }
    }
    
    version = 2
    proposals = aes128-sha256-modp2048
    rekey_time = 28800s
  }
}

secrets {
  ike-isp1 {
    id = $ISP1_REMOTE
    secret = "$PSK"
  }
  ike-isp2 {
    id = $ISP2_REMOTE
    secret = "$PSK"
  }
  ike-slu2 {
    id = $LOCAL_IP
    secret = "$PSK"
  }
}
EOF

fi

echo ""
echo "✓ Configuration files created successfully!"
echo ""
echo "Next steps:"
echo "1. sudo systemctl restart strongswan-swanctl"
echo "2. sudo swanctl --load-all"
echo "3. sudo swanctl --initiate --child tunnel-isp1"
echo "4. sudo swanctl --initiate --child tunnel-isp2"
echo ""
echo "To check tunnel status:"
echo "   sudo swanctl --list-conns"
echo "   sudo swanctl --list-sas"
echo ""
echo "To switch between tunnels (from your failover script):"
echo "   sudo swanctl --terminate --ike tunnel-isp1"
echo "   sudo swanctl --initiate --child tunnel-isp2"
echo ""