{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;
  vars = import ./vars.nix;
  allNodeIps = [ cfg.privateAddress ] ++ cfg.cluster.otherNodes;
  # The public VIP carries a /32 suffix for keepalived; strip it for nftables rules.
  publicVipAddr = lib.head (lib.splitString "/" vars.virtualIpAddress);

  inherit (vars)
    kubeadmVersion
    kubeletVersion
    apiserverVip
    primaryInterface
    podCidr
    nodeLabels
    k8sAdminConf
    k8sSuperAdminConf
    k8sManifestsDir
    k8sBootstrapYaml
    k8sJoinYamlTpl
    k8sJoinYaml
    kubevipImage
    vrrpInterfaceSubnet
    vrrpInstanceName
    vrrpRouterId
    vrrpState
    virtualIpAddress
    brexVrrpInstanceName
    brexVrrpRouterId
    brexVrrpInterface
    brexVirtualIpAddress
    kubeletBootstrapConf
    kubeletConf
    kubeletConfigYaml
    kubeletConfigDir
    ;

  # Kubelet arguments as a single string
  kubeletNodeLabelsString = lib.concatStringsSep "," nodeLabels;
  kubeletKubeconfigArgs = "--bootstrap-kubeconfig=${kubeletBootstrapConf} --kubeconfig=${kubeletConf} --node-ip=${cfg.privateAddress} --node-labels=${kubeletNodeLabelsString}";
  kubeletConfigArgs = "--config=${kubeletConfigYaml} --config-dir=${kubeletConfigDir}";
  installKubevip = import ./scripts/installKubevip.nix {
    inherit
      pkgs
      k8sAdminConf
      k8sSuperAdminConf
      kubevipImage
      primaryInterface
      apiserverVip
      k8sManifestsDir
      ;
  };
  initKubeadm = import ./scripts/initKubeadm.nix {
    inherit
      pkgs
      k8sBootstrapYaml
      k8sAdminConf
      ;
  };
  joinCPKubeadm = import ./scripts/joinCPKubeadm.nix {
    inherit
      pkgs
      k8sJoinYamlTpl
      k8sJoinYaml
      k8sAdminConf
      ;
  };
in
{
  options.customNixOSModules.rpcuIaaSCP = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the RPCU IaaS Control Plane module for Kubernetes cluster setup";
    };

    privateAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Private IP address for the node";
    };

    primaryMacAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "MAC address of the primary network interface (eno1)";
    };

    openstackMacAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "MAC address of the OpenStack network interface (enp3s0)";
    };

    cluster = lib.mkOption {
      type = lib.types.submodule {
        options = {
          priority = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "VRRP priority for keepalived cluster failover (higher = preferred)";
          };

          otherNodes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of other control plane node IP addresses for cluster communication";
          };
        };
      };
      default = { };
      description = "Kubernetes cluster configuration options";
    };

    publicIngress = lib.mkOption {
      default = { };
      description = ''
        Route external HTTP(S) ingress traffic arriving on the public failover
        VIP (keepalived VI_1, ${virtualIpAddress} on ${primaryInterface}) into a
        tenant/workload cluster's Octavia LoadBalancer VIP via DNAT.

        The DNAT rule is installed on all three control-plane nodes but only the
        current VRRP master holds the public VIP, so forwarding follows failover
        automatically (VI_1 and VI_2 share the same priorities/peers, so the
        master also owns the route into the 172.16.0.0/16 Octavia network).
      '';
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable DNAT forwarding from the public VIP to a tenant Octavia LoadBalancer VIP";
          };

          targetVip = lib.mkOption {
            type = lib.types.str;
            example = "172.16.255.10";
            description = ''
              The tenant cluster's Octavia LoadBalancer VIP (a floating IP from
              the external network pool 172.16.255.1-254) that the public VIP
              should forward ingress traffic to. Pin this on the tenant ingress
              Service via its loadBalancerIP so it stays stable.
            '';
          };

          ports = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [
              80
              443
            ];
            description = "TCP ports to forward from the public VIP to the target Octavia VIP";
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    import ./osconfig.nix {
      inherit
        lib
        cfg
        pkgs
        config
        installKubevip
        initKubeadm
        joinCPKubeadm
        kubeadmVersion
        apiserverVip
        podCidr
        nodeLabels
        kubeletKubeconfigArgs
        kubeletConfigArgs
        vrrpInstanceName
        vrrpInterfaceSubnet
        vrrpState
        vrrpRouterId
        virtualIpAddress
        brexVrrpInstanceName
        brexVrrpRouterId
        brexVrrpInterface
        brexVirtualIpAddress
        primaryInterface
        allNodeIps
        publicVipAddr
        ;
    }
    // {
      customNixOSModules = {
        # Secure sysctl settings
        sysctlSecure.enable = true;

        # Network management and virtual switching
        vlanConfiguration = {
          enable = true;
          vswitch = {
            enable = true;
            interface = primaryInterface;
            vlans = [
              {
                vlanId = 4000;
                inherit (cfg) privateAddress;
                prefixLength = 24;
              }
            ];
          };
        };
        kubernetes = {
          enable = true;
          version = {
            kubeadm = kubeadmVersion;
            kubelet = kubeletVersion;
          };
          kubeadmUpgrade.enable = true;
        };
        caCertificates = {
          didactiklabs.enable = true;
          rpcu.enable = true;
        };
        ginx.enable = true;
        chrony.enable = true;
      };
    }
  );
}
