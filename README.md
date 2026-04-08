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

