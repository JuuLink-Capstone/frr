# FRR Config

This repository contains research into FRR configurations used by the Juulink Capstone project. We are utilizing FRR as an alternative to SD-WAN for providing and testing multi-WAN redundancy. To that end, in particular we are interested in researching these specific parts of FRR:

* WAN failover via BGP configuration
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
* `frr.conf` does something, not confident on this one yet.
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


### Kevin's recommendations:

* BGP
* OSPF
* Hot-swap router protocol (VRRP?)
* Route maps may be important for preserving IPSEC tunnels for the church's stuff. Can we keep it up?
* Access control lists or firewalld? perhaps
* NAT functionality? Do we masquerade in the Linux kernel, or pull it into FRR? 

* 1. H-config, do we need router 1 aware of router 2? Or can we blindly forward when a route goes down. SLU treats the other as an ISP.
* 2. H-config, have router 1 and 2 aware of each other, what the tradeoffs are of both configurations.

### Kevin's questions

* How do we determine with high accuracy when the Versa switches over to a new link? 
* Probe the overlay and the underlay. I think that the overlay is the flow of data from one endpoint to another, while the underlay is the actual route that is taken.
* Test 2: both Versas, when the left Versa has a link go bad, how long does it take Versa to decide to switch to another one. Detect when Versa decides to switch, and when the switch effectively takes place. 

* Can we omit the church's IPSEC tunnels from the failover / switchover? AAA is Authentication Authorization and Accounting, keeps track of devices that have accepted the agreement for the wifi.