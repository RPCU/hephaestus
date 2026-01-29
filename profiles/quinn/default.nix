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
  kubevipVersion = "v1.0.3";
  installKubevip = pkgs.writeShellScriptBin "installKubevip" ''
    set -euo pipefail
    ctr image pull ghcr.io/kube-vip/kube-vip:${kubevipVersion} ;
    kubevip="ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${kubevipVersion} vip /kube-vip"
    $kubevip manifest pod \
      --interface ${privateInterface}.4000 \
      --address ${apiserverVip} \
      --controlplane --services --arp --leaderElection \
      --k8sConfigPath=/etc/kubernetes/admin.conf | \
      tee /etc/kubernetes/manifests/kube-vip.yaml
  '';
  joinCPKubeadm = pkgs.writeShellScriptBin "joinCPKubeadm" ''
    set -euo pipefail

    # Display help if requested or if arguments are missing
    if [[ "$\{1:-}" == "--help" || "$\{1:-}" == "-h" || $# -lt 2 ]]; then
      echo "Usage: joinKubeadm <TOKEN> <CERTIFICATE_KEY>"
      echo ""
      echo "Arguments:"
      echo "  TOKEN              The bootstrap token (e.g., abcdef.1234567890abcdef)"
      echo "  CERTIFICATE_KEY    The hex encryption key for control-plane certificates"
      echo ""
      echo "Description:"
      echo "  This script populates the join.yaml template and joins the node to"
      echo "  the Kubernetes cluster as a control-plane member."
      exit 0
    fi

    TOKEN=$1
    CERT_KEY=$2

    echo "Populating join configuration..."
    sed -e "s/__TOKEN__/$TOKEN/g" \
        -e "s/__CERTIFICATE_KEY__/$CERT_KEY/g" \
        /etc/kubernetes/kubeadm/join.yaml.tpl > /etc/kubernetes/kubeadm/join.yaml

    echo "Joining cluster..."
    kubeadm join --config /etc/kubernetes/kubeadm/join.yaml
    installKubevip
    echo ""
    echo "Configuring kubectl access..." >&2
    mkdir -p "$HOME/.kube"
    cp /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
    echo "---"
    kubectl get no -o wide
    echo "---"
  '';
in
{
  environment = {
    systemPackages = [
      joinCPKubeadm
      installKubevip
    ];
    etc = {
      "kubernetes/kubeadm/join.yaml.tpl".text = ''
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: JoinConfiguration
        nodeRegistration:
          taints: []
        controlPlane:
          localAPIEndpoint:
            advertiseAddress: '${privateAddress}'
            bindPort: 6443
          certificateKey: '__CERTIFICATE_KEY__'
        discovery:
          bootstrapToken:
            token: '__TOKEN__'
            unsafeSkipCAVerification: true
            apiServerEndpoint: "${apiserverVip}:6443"
      '';
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
