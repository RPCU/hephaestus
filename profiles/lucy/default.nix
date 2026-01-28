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
  privateAddress = "10.0.0.2";
in
{
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
        interface = "eno1";
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
