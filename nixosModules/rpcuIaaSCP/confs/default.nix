# Imports all Kubernetes configuration files for environment.etc
{
  lib,
  cfg,
  kubeadmVersion,
  apiserverVip,
  podCidr,
  nodeLabels,
  allNodeIps,
}:
let
  auditPolicy = import ./audit-policy.nix { };
  kubelet00Config = import ./kubelet-00-config.nix { };

  kubelet10Config = import ./kubelet-10-config.nix { inherit cfg; };
  resolvK8s = import ./resolv-k8s.nix { inherit cfg; };
  kubeadmBootstrap = import ./kubeadm-bootstrap.nix {
    inherit
      lib
      cfg
      kubeadmVersion
      apiserverVip
      podCidr
      allNodeIps
      ;
  };
  kubeadmJoinTemplate = import ./kubeadm-join-template.nix { inherit apiserverVip cfg; };
in
{
  baseConfigs = auditPolicy // kubelet00Config;
  clusterConfigs = kubelet10Config // resolvK8s // kubeadmBootstrap // kubeadmJoinTemplate;
}
