# Setup & Usage

#### Prerequisites

Ubuntu/Debian-based Linux system
Two active WAN interfaces (e.g. ens4, ens5)
Root or sudo access
The following companion scripts in the same directory as install.sh:

- s2-check-starlink.sh
- s2-failover.sh
- s2-route-decision-loop.sh


#### Step 1 — Download and set permissions
After downloading the scripts, you must mark install.sh as executable before it can be run:
bashchmod +x install.sh
If you also need to set permissions on the companion scripts manually:
bashchmod +x s2-check-starlink.sh s2-failover.sh s2-route-decision-loop.sh

#### Step 2 — Run the installer
bashsudo ./install.sh

The script will automatically escalate to root if you run it without sudo.


#### Step 3 — Answer the prompts
The installer will ask you five questions. All three threshold values have sensible defaults — just press Enter to accept them.
Interfaces

Primary WAN interface — the network interface for your main internet connection (e.g. ens4)
Backup WAN interface — the interface for your failover connection (e.g. ens5)

SLA Thresholds — failover triggers when any of these are exceeded:

Packet loss — percentage of dropped packets before switching over (default: 5%)
Latency — round-trip time in milliseconds (default: 150ms)
Jitter — variation in latency in milliseconds (default: 30ms)

Once you've entered your values, the installer will display a summary. Review it, then type y and press Enter to begin.
Not sure what your interface names are? Run ip link show in a separate terminal to list all available network interfaces.

What the installer does

Installs required packages (fping, bc, iptables-persistent)
Enables IPv4 forwarding
Configures NAT masquerading on both WAN interfaces
Copies monitoring and failover scripts to /usr/local/bin/
Applies your SLA thresholds to the check script
Creates and enables a wan-failover systemd service that starts automatically on boot


#### Verifying the installation
Check that the service is running:
bashsystemctl status wan-failover

#### Viewing logs
bash# Failover events
journalctl -t failover -f

#### Primary interface health checks
journalctl -t starlink-check-ens4 -f

#### Backup interface health checks
journalctl -t starlink-check-ens5 -f




Uninstalling
To stop and remove the service:
bashsudo systemctl stop wan-failover
sudo systemctl disable wan-failover
sudo rm /etc/systemd/system/wan-failover.service
sudo systemctl daemon-reload
To remove the installed scripts:
bashsudo rm /usr/local/bin/s2-check-starlink.sh
sudo rm /usr/local/bin/s2-failover.sh
sudo rm /usr/local/bin/s2-route-decision-loop.sh
