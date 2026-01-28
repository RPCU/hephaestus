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
  kubeadmVersion = "v1.35.0";
  apiserverVip = "10.0.0.5";
  privateInterface = "eno1";
  initKubeadm = pkgs.writeShellScriptBin "initKubeadm" ''
    set -euo pipefail
      installKubevip
      kubeadm init --config /etc/kubernetes/kubeadm/bootstrap.yaml --upload-certs
  '';
in
{
  environment = {
    systemPackages = [
      initKubeadm
    ];
    etc = {
      "kubernetes/kubelet/config.d/10-config.conf".text = ''
        kind: KubeletConfiguration
        apiVersion: kubelet.config.k8s.io/v1beta1
        address: "${privateAddress}"
      '';
      "kubernetes/kubeadm/bootstrap.yaml".text = ''
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: ClusterConfiguration
        networking:
          serviceSubnet: '10.96.0.0/20'
          podSubnet: '10.244.0.0/16'
        kubernetesVersion: '${kubeadmVersion}'
        controlPlaneEndpoint: '${apiserverVip}'
        apiServer:
          certSANs:
            - 'openstack.rpcu.lan'
            -  '${apiserverVip}'
          extraArgs:
            enable-admission-plugins: DefaultTolerationSeconds
            bind-address: "${privateAddress}"
        ---
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: InitConfiguration
        skipPhases:
          - addon/kube-proxy
        localAPIEndpoint:
          advertiseAddress: '${privateAddress}'
          bindPort: 6443
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
        kubeadm = "${kubeadmVersion}";
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
