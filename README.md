# FRR Config

This repository contains research into FRR configurations used by the Juulink Capstone project. We are utilizing FRR as an alternative to SD-WAN for providing and testing multi-WAN redundancy. To that end, in particular we are interested in researching these specific parts of FRR:

* WAN failover via BGP configuration (see [bgp fast-external-failover](https://docs.frrouting.org/en/latest/bgp.html#clicmd-bgp-fast-external-failover)).
* WAN failover via policy routing (route maps)
* WAN failover informed by DLEP information
* FRR NAT support
* Load balancing via ECMP (Equal-Cost Multi-Path), which may also provide failover

### FRR Configuration How to

FRR configuration files are located in `/etc/frr`. They follow this structure:
```
/etc/frr
 ├- daemons
 ├- frr.conf
 ├- frr.conf.sav
 ├- support_bundle_commands.conf
 └- vtysh.conf
```

* `daemons` contains a list of enabled/disabled daemons, with names such as bgpd, ripd, etc. Each daemon is responsible for a protocol, like bgpd is responsible for BGP.
* `frr.conf` contains the configuration for frr as a whole, as well as all of the per-daemon configuration.
* `frr.conf.sav` seems like some sort of backup? I'm not sure.
* `support_bundle_commands.conf` seems to contain a list of vytsh commands? I'm not sure on this.
* `vtysh.conf` only contains one line. I don't know what it does.

I think that `daemons` and `frr.conf` are intended to be editted, either manually or via vtysh commands.

### FRR Testing 

It is important to be able to perform individual unit tests on each of the FRR systems that we plan on using. That means we will need tests for the following:

* BGP configuration
* Route maps
* DLEP
* FRR NAT
* ECMP ("[can be inspected in zebra by doing a `show ip route X` command](https://docs.frrouting.org/en/latest/zebra.html#ecmp)")
* FRR configuration input (what cli options can be used to input an arbitrary config file)


Dual-WAN Failover — Setup & Usage
Prerequisites

Ubuntu/Debian-based Linux system
Two active WAN interfaces (e.g. ens4, ens5)
Root or sudo access
The following companion scripts in the same directory as install.sh:

s2-check-starlink.sh
s2-failover.sh
s2-route-decision-loop.sh


Step 1 — Download and set permissions
After downloading the scripts, you must mark install.sh as executable before it can be run:
bashchmod +x install.sh
If you also need to set permissions on the companion scripts manually:
bashchmod +x s2-check-starlink.sh s2-failover.sh s2-route-decision-loop.sh

Step 2 — Run the installer
bashsudo ./install.sh

The script will automatically escalate to root if you run it without sudo.


Step 3 — Answer the prompts
The installer will walk you through a short series of questions:
PromptExample inputDescriptionPrimary WAN interfaceens4Your main internet-facing interfaceBackup WAN interfaceens5Your failover interfacePacket loss threshold %5Failover triggers above this loss percentageLatency threshold ms150Failover triggers above this latencyJitter threshold ms30Failover triggers above this jitter value
All thresholds have defaults — just press Enter to accept them.
After reviewing the configuration summary, type y and press Enter to proceed.

What the installer does

Installs required packages (fping, bc, iptables-persistent)
Enables IPv4 forwarding
Configures NAT masquerading on both WAN interfaces
Copies monitoring and failover scripts to /usr/local/bin/
Applies your SLA thresholds to the check script
Creates and enables a wan-failover systemd service that starts automatically on boot


Verifying the installation
Check that the service is running:
bashsystemctl status wan-failover

Viewing logs
bash# Failover events
journalctl -t failover -f

# Primary interface health checks
journalctl -t starlink-check-ens4 -f

# Backup interface health checks
journalctl -t starlink-check-ens5 -f

Replace ens4 / ens5 with the interface names you configured during install.


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
