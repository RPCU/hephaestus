{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;
  vars = import ./vars.nix;
  allNodeIps = [ cfg.cluster.privateAddress ] ++ cfg.cluster.otherNodes;

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
    kubeletBootstrapConf
    kubeletConf
    kubeletConfigYaml
    kubeletConfigDir
    ;

  # Cluster enablement flag
  isClusterEnabled = cfg.cluster.privateAddress != "";

  # Shell snippet: apply node labels

  # Kubelet arguments as a single string
  kubeletNodeLabelsString = lib.concatStringsSep "," nodeLabels;
  kubeletKubeconfigArgs = "--bootstrap-kubeconfig=${kubeletBootstrapConf} --kubeconfig=${kubeletConf} --node-ip=${cfg.cluster.privateAddress} --node-labels=${kubeletNodeLabelsString}";
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

    cluster = lib.mkOption {
      type = lib.types.submodule {
        options = {
          privateAddress = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Private IP address for the cluster node (enables cluster mode when set)";
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
  };

  config = lib.mkIf cfg.enable (
    import ./osconfig.nix {
      inherit
        lib
        cfg
        pkgs
        config
        isClusterEnabled
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
        primaryInterface
        allNodeIps
        ;
    }
    // {
      # Custom NixOS module configurations for cluster
      customNixOSModules = lib.mkIf isClusterEnabled {
        # Secure sysctl settings
        sysctlSecure.enable = true;

        # Network management and virtual switching
        networkManager = {
          enable = true;
          vswitch = {
            enable = true;
            interface = primaryInterface;
            vlans = [
              {
                vlanId = 4000;
                inherit (cfg.cluster) privateAddress;
                prefixLength = 24;
              }
            ];
          };
        };
        # Kubernetes deployment configuration
        kubernetes = {
          enable = true;
          version = {
            kubeadm = kubeadmVersion;
            kubelet = kubeletVersion;
          };
        };
        # Certificates and security
        caCertificates.didactiklabs.enable = true;
        # Web server and time synchronization
        ginx.enable = true;
        chrony.enable = true;
      };
    }
  );
}
