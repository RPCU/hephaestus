# Cluster-specific kubelet configuration (cluster nodes only)
{ cfg }:
{
  "kubernetes/kubelet/config.d/10-config.conf".text = ''
    kind: KubeletConfiguration
    apiVersion: kubelet.config.k8s.io/v1beta1
    address: "${cfg.privateAddress}"
    # Hand pods a resolver that knows the Designate `rpcu.lan` zone instead of
    # the host's public-only resolvers. CoreDNS uses `dnsPolicy: Default`, so it
    # inherits this file and forwards `.` to the node-local dnsmasq, which in
    # turn splits `rpcu.lan` off to the in-cluster PowerDNS (10.0.0.241).
    # See confs/resolv-k8s.nix for the full rationale.
    resolvConf: /etc/resolv-k8s.conf
  '';
}
