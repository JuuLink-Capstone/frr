#!/bin/bash

# StrongSwan Tunnel Configuration Script with Interactive Prompts

set -e

echo "=========================================="
echo "StrongSwan Tunnel Configuration"
echo "=========================================="
echo ""

# Prompt for node type
echo "What type of node is this?"
echo "1) SLU1 (Initiator)"
echo "2) Internet Node (Responder)"
read -p "Enter choice (1 or 2): " node_choice

if [ "$node_choice" = "1" ]; then
    NODE_TYPE="slu1"
elif [ "$node_choice" = "2" ]; then
    NODE_TYPE="internet"
else
    echo "Error: Invalid choice. Please enter 1 or 2."
    exit 1
fi

echo ""
read -p "Enter this node's IP address: " LOCAL_IP
read -p "Enter the remote node's IP address: " REMOTE_IP
read -sp "Enter the pre-shared key: " PSK
echo ""

# Validate inputs
if [ -z "$LOCAL_IP" ] || [ -z "$REMOTE_IP" ] || [ -z "$PSK" ]; then
    echo "Error: All fields are required."
    exit 1
fi

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo "Node Type: $NODE_TYPE"
echo "Local IP: $LOCAL_IP"
echo "Remote IP: $REMOTE_IP"
echo "Pre-shared Key: ****"
echo ""

read -p "Proceed with configuration? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Setting up StrongSwan for $NODE_TYPE node..."

# Create config directory
sudo mkdir -p /etc/swanctl/conf.d

# ==================== SLU1 Setup ====================
if [ "$NODE_TYPE" = "slu1" ]; then
    echo "Creating tunnel.conf for SLU1..."
    
    sudo tee /etc/swanctl/conf.d/tunnel.conf > /dev/null <<EOF
connections {
  tunnel-to-internet {
    local_addrs = $LOCAL_IP
    remote_addrs = $REMOTE_IP
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel {
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
  ike-tunnel {
    id = $LOCAL_IP
    secret = "$PSK"
  }
}
EOF

    echo "Creating internet.conf for remote identity..."
    
    sudo tee /etc/swanctl/conf.d/internet.conf > /dev/null <<EOF
secrets {
  ike-internet {
    id = $REMOTE_IP
    secret = "$PSK"
  }
}
EOF

# ==================== Internet Node Setup ====================
elif [ "$NODE_TYPE" = "internet" ]; then
    echo "Creating tunnel.conf for Internet Node..."
    
    sudo tee /etc/swanctl/conf.d/tunnel.conf > /dev/null <<EOF
connections {
  tunnel-from-slu1 {
    local_addrs = $LOCAL_IP
    remote_addrs = $REMOTE_IP
    
    local {
      auth = psk
    }
    remote {
      auth = psk
    }
    
    children {
      tunnel {
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
  ike-internet {
    id = $LOCAL_IP
    secret = "$PSK"
  }
  ike-slu1 {
    id = $REMOTE_IP
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
echo "3. sudo swanctl --initiate --child tunnel"
echo ""