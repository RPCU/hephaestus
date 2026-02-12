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
  privateAddressLucy = "10.0.0.2";
  privateAddressMakise = "10.0.0.3";
  apiserverVip = "10.0.0.5";
  privateInterface = "eno1";
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
    kubectl label --overwrite nodes --all openstack-control-plane=enabled
    kubectl label --overwrite nodes --all openstack-compute-node=enabled
    kubectl label --overwrite nodes --all openvswitch=enabled
    kubectl label --overwrite nodes --all linuxbridge=enabled
    kubectl get no -o wide --show-labels
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
  systemd.network.links."00-eno1" = {
    matchConfig.PermanentMACAddress = "4c:52:62:0a:82:93";
    linkConfig.Name = "eno1";
  };
  systemd = {
    services = {
      kubelet = {
        serviceConfig = {
          Environment = [
            ''KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --node-ip=${privateAddress} --node-labels=openstack-control-plane=enabled,openstack-compute-node=enabled,openvswitch=enabled,linuxbridge=enabled"''
          ];
        };
      };
    };
  };
  services.keepalived = {
    enable = true;
    vrrpInstances.VI_1 = {
      interface = "${privateInterface}.4000";
      state = "BACKUP";
      virtualRouterId = 51;
      priority = 98;
      unicastSrcIp = "${privateAddress}";
      unicastPeers = [
        "${privateAddressLucy}"
        "${privateAddressMakise}"
      ];
      virtualIps = [
        {
          addr = "178.63.143.219/32";
          dev = "${privateInterface}";
        }
      ];
    };
  };
  customNixOSModules = {
    rpcuIaaSCP.enable = true;
    sysctlSecure.enable = true;
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
        kubeadm = "v1.35.1";
        kubelet = "v1.35.1";
      };
    };
    caCertificates = {
      didactiklabs.enable = true;
    };
    ginx.enable = true;
    chrony.enable = true;
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
