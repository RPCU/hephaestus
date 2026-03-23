# Imports all Kubernetes configuration files for environment.etc
{
  lib,
  cfg,
  kubeadmVersion,
  apiserverVip,
  podCidr,
}:
let
  auditPolicy = import ./audit-policy.nix { };
  kubelet00Config = import ./kubelet-00-config.nix { };

  kubelet10Config = import ./kubelet-10-config.nix { inherit cfg; };
  kubeadmBootstrap = import ./kubeadm-bootstrap.nix {
    inherit
      lib
      cfg
      kubeadmVersion
      apiserverVip
      podCidr
      ;
  };
  kubeadmJoinTemplate = import ./kubeadm-join-template.nix { inherit apiserverVip cfg; };
in
{
  baseConfigs = auditPolicy // kubelet00Config;
  clusterConfigs = kubelet10Config // kubeadmBootstrap // kubeadmJoinTemplate;
}
