{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  privateAddress = "10.0.0.3";
  kubevipVersion = "v1.0.3";
  apiserverVip = "10.0.0.5";
  privateInterface = "eno1";
  privateVlanid = "4000";
  installKubevip = pkgs.writeShellScriptBin "installKubevip" ''
    set -euo pipefail
    alias kubevip="ctr image pull ghcr.io/kube-vip/kube-vip:${kubevipVersion}; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${kubevipVersion} vip /kube-vip"
    kube-vip manifest pod --interface ${privateInterface}.${privateVlanid} --address ${apiserverVip} --controlplane --services --arp --leaderElection --k8sConfigPath=/etc/kubernetes/admin.conf | tee /etc/kubernetes/manifests/kube-vip.yaml
  '';
in
{
  environment = {
    systemPackages = [
      installKubevip
    ];
    etc = {
      "kubernetes/kubelet/config.d/10-config.conf".text = ''
        kind: KubeletConfiguration
        apiVersion: kubelet.config.k8s.io/v1beta1
        address: "${privateAddress}"
      '';
    };
  };
  systemd = {
    services = {
      kubelet = {
        serviceConfig = {
          Environment = [
            ''KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --node-ip=${privateAddress}"''
          ];
        };
      };
    };
  };
  customNixOSModules = {
    rpcuIaaSCP.enable = true;
    networkManager = {
      enable = true;
      vswitch = {
        enable = true;
        interface = "${privateInterface}";
        privateAddress = "${privateAddress}";
      };
    };
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "v1.35.0";
        kubelet = "v1.35.0";
      };
    };
    caCertificates = {
      didactiklabs.enable = true;
    };
    ginx.enable = true;
  };
  imports = [
    (import ../../users/rpcu {
      inherit
        config
        pkgs
        lib
        sources
        overrides
        ;
    })
  ];
}
