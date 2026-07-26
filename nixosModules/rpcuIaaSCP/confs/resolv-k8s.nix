# Dedicated resolv.conf handed to the kubelet via `resolvConf:` (see
# kubelet-10-config.nix), NOT the host's own /etc/resolv.conf.
#
# WHY THIS EXISTS
# ---------------
# The Designate zone `rpcu.lan` is served by the PowerDNS authoritative server
# running inside this very cluster (LoadBalancer 10.0.0.241). The host's
# /etc/resolv.conf points at Hetzner's public resolvers (185.12.64.1/2), which
# know nothing about `rpcu.lan`. CoreDNS runs with `dnsPolicy: Default`, so it
# inherits whatever the kubelet hands it and therefore forwarded `.` to those
# public resolvers too — meaning NOTHING in the cluster could resolve a
# `*.rpcu.lan` name:
#
#   dig mimir.mgmt.rpcu.lan   -> no such host   (from any pod)
#
# The concrete breakage this caused: the openstack cluster's Prometheus
# remote_writes to `https://mimir.mgmt.rpcu.lan/api/v1/push`, so every batch
# failed with
#
#   "dial tcp: lookup mimir.mgmt.rpcu.lan on 10.96.0.10:53: no such host"
#
# and the openstack cluster was completely absent from the central Grafana.
# The network path itself was always fine (TCP+TLS to the gateway succeed) —
# only name resolution was missing.
#
# WHY A SEPARATE FILE INSTEAD OF `networking.nameservers`
# ------------------------------------------------------
# Pointing the HOST's resolv.conf at dnsmasq would also work, but it makes
# dnsmasq a hard dependency for *all* host DNS — container image pulls, netbird,
# node bootstrap — and it has to be reconciled with systemd-networkd's
# DHCP-supplied DNS and netbird's resolv.conf management. A mistake there takes
# a baremetal control-plane node off the network. Scoping the change to the
# kubelet keeps the blast radius inside the cluster and makes rollback a single
# config line.
#
# Note it must NOT be `127.0.0.1`: pods get this file's contents verbatim, and
# inside a pod's network namespace 127.0.0.1 is the POD itself, not the node.
# Hence the node's routable VLAN address, which is why dnsmasq is bound to the
# VLAN interface in osconfig.nix.
#
# The `search` list mirrors what the host currently hands out so pod resolution
# behaviour is otherwise unchanged (kubelet appends the cluster suffixes ahead
# of these for `ClusterFirst` pods).
{ cfg }:
{
  "resolv-k8s.conf".text = ''
    nameserver ${cfg.privateAddress}
    search openstack.rpcu.vpn rpcu.lan netbird.selfhosted rpcu.vpn
  '';
}
