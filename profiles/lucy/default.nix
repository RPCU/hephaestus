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
  privateAddressMakise = "10.0.0.3";
  privateAddressQuinn = "10.0.0.4";
  kubeadmVersion = "v1.35.1";
  apiserverVip = "10.0.0.5";
  primaryInterface = "eno1";
  kubevipVersion = "v1.0.4";
  podCidr = "10.244.0.0/16";
  installKubevip = pkgs.writeShellScriptBin "installKubevip" ''
    set -euo pipefail
    ctr image pull ghcr.io/kube-vip/kube-vip:${kubevipVersion} ;
    kubevip="ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${kubevipVersion} vip /kube-vip"
    $kubevip manifest pod \
      --interface ${primaryInterface}.4000 \
      --address ${apiserverVip} \
      --controlplane --services --arp --leaderElection \
      --k8sConfigPath=/etc/kubernetes/super-admin.conf | \
      tee /etc/kubernetes/manifests/kube-vip.yaml
  '';
  initKubeadm = pkgs.writeShellScriptBin "initKubeadm" ''
    set -euo pipefail

    # 1. Help Menu Logic
    if [[ "$\{@:-}" == *"--help"* || "$\{@:-}" == *"-h"* ]]; then
      echo "Usage: initKubeadm"
      echo ""
      echo "Description:"
      echo "  - Deploys kubevip manifests for HA."
      echo "  - Initializes the Kubernetes cluster using bootstrap.yaml."
      echo "  - Filters output to display ONLY the join token and certificate key."
      exit 0
    fi

    # 2. Setup Static Pods
    installKubevip

    # 3. Run Init and Extract Credentials
    # We redirect stdout to a temporary variable to parse it
    echo "Initializing cluster (this may take a minute)..." >&2
    OUTPUT=$(kubeadm init --config /etc/kubernetes/kubeadm/bootstrap.yaml --upload-certs)
    kubevip="ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${kubevipVersion} vip /kube-vip"
    $kubevip manifest pod \
      --interface ${primaryInterface}.4000 \
      --address ${apiserverVip} \
      --controlplane --services --arp --leaderElection \
      --k8sConfigPath=/etc/kubernetes/admin.conf | \
      tee /etc/kubernetes/manifests/kube-vip.yaml


    TOKEN=$(echo "$OUTPUT" | grep -oP '(?<=--token )[^ ]+' | head -n 1)
    CERT_KEY=$(echo "$OUTPUT" | grep -oP '(?<=--certificate-key )[^ ]+' | head -n 1)

    echo "Configuring kubectl access..." >&2
    mkdir -p "$HOME/.kube"
    cp /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"

    echo "--------------------------------------------------"
    echo "CLUSTER INITIALIZED SUCCESSFULLY"
    echo "--------------------------------------------------"

    # 2. Print the helper command
    echo "---"
    kubectl label --overwrite nodes --all openstack-control-plane=enabled
    kubectl label --overwrite nodes --all openstack-compute-node=enabled
    kubectl label --overwrite nodes --all openvswitch=enabled
    kubectl label --overwrite nodes --all linuxbridge=enabled
    kubectl get no -o wide --show-labels
    echo "---"
    echo ""
    if [[ -n "$TOKEN" && -n "$CERT_KEY" ]]; then
        echo "To join another Control Plane node, run:"
        echo ""
        echo "joinCPKubeadm $TOKEN $CERT_KEY"
    else
        echo "Error: Could not extract join credentials from kubeadm output."
        exit 1
    fi
  '';
in
{
  environment = {
    systemPackages = [
      initKubeadm
      installKubevip
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
        clusterName: 'openstack'
        networking:
          serviceSubnet: '10.96.0.0/20'
          podSubnet: '${podCidr}'
          dnsDomain: 'openstack.local'
        kubernetesVersion: '${kubeadmVersion}'
        controlPlaneEndpoint: '${apiserverVip}'
        apiServer:
          certSANs:
            - 'openstack.rpcu.lan'
            - '${apiserverVip}'
            - '${privateAddress}'
            - '${privateAddressQuinn}'
            - '${privateAddressMakise}'
          extraArgs:
            enable-admission-plugins: DefaultTolerationSeconds
            audit-policy-file: '/etc/kubernetes/audit/policy.yaml'
            audit-log-path: '/var/log/kubernetes_audit.log'
            audit-log-maxsize: '100'
            audit-log-maxbackup: '10'
            audit-log-mode: 'batch'
            audit-log-batch-max-size: '5'
          extraVolumes:
            - name: auditpolicy
              hostPath: /etc/kubernetes/audit/policy.yaml
              mountPath: /etc/kubernetes/audit/policy.yaml
        ---
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: InitConfiguration
        skipPhases:
          - addon/kube-proxy
        localAPIEndpoint:
          advertiseAddress: '${privateAddress}'
          bindPort: 6443
        nodeRegistration:
          taints: []
      '';
    };
  };
  systemd.network.links."00-eno1" = {
    matchConfig.PermanentMACAddress = "b4:2e:99:cd:02:76";
    linkConfig.Name = "eno1";
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
  services.keepalived = {
    enable = true;
    vrrpInstances.VI_1 = {
      interface = "${primaryInterface}.4000";
      state = "BACKUP";
      virtualRouterId = 51;
      priority = 100;
      unicastSrcIp = "${privateAddress}";
      unicastPeers = [
        "${privateAddressMakise}"
        "${privateAddressQuinn}"
      ];
      virtualIps = [
        {
          addr = "178.63.143.219/32";
          dev = "${primaryInterface}";
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
        interface = "${primaryInterface}";
        vlans = [
          {
            vlanId = 4000;
            privateAddress = "${privateAddress}";
            prefixLength = 24;
            mtu = 1400;
          }
          {
            vlanId = 4001;
            privateAddress = "10.10.0.2";
            prefixLength = 16;
            mtu = 1400;
          }
        ];
      };
    };
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "${kubeadmVersion}";
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
