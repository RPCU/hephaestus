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
  privateAddress = "10.0.0.4";
  apiserverVip = "10.0.0.5";
  privateInterface = "enp0s31f6";
in
{
  networking = {
    firewall.extraInputRules = ''
      # Allow 6443 only for this specific destination IP
      ip daddr 127.0.0.1 tcp dport 6443 accept
      ip daddr ${privateAddress} tcp dport 6443 accept
      ip daddr ${apiserverVip} tcp dport 6443 accept
    '';
  };
  environment = {
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
