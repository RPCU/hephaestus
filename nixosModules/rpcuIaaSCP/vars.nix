# Pure constants for the RPCU IaaS Control Plane module.
# No function arguments — this is a plain attribute set.
let
  # Kubernetes versioning
  kubeadmVersion = "v1.35.3";
  kubeletVersion = "v1.35.3";
  kubevipVersion = "v1.0.4";

  # Network configuration
  apiserverVip = "10.0.0.5";
  primaryInterface = "eno1";
  podCidr = "10.244.0.0/16";

  # Kubernetes paths
  k8sEtcDir = "/etc/kubernetes";
in
{
  # Kubernetes versioning
  inherit kubeadmVersion kubeletVersion kubevipVersion;

  # Network configuration
  inherit apiserverVip primaryInterface podCidr;

  # Kubernetes paths
  inherit k8sEtcDir;
  k8sManifestsDir = "${k8sEtcDir}/manifests";
  k8sAdminConf = "${k8sEtcDir}/admin.conf";
  k8sSuperAdminConf = "${k8sEtcDir}/super-admin.conf";
  k8sBootstrapYaml = "${k8sEtcDir}/kubeadm/bootstrap.yaml";
  k8sJoinYamlTpl = "${k8sEtcDir}/kubeadm/join.yaml.tpl";
  k8sJoinYaml = "${k8sEtcDir}/kubeadm/join.yaml";

  # Docker image references
  kubevipImage = "ghcr.io/kube-vip/kube-vip:${kubevipVersion}";

  # Node labels (as a list for easier iteration)
  nodeLabels = [
    "openstack-control-plane=enabled"
    "openstack-compute-node=enabled"
    "openvswitch=enabled"
    "linuxbridge=enabled"
  ];

  # Keepalived VRRP configuration
  vrrpInterfaceSubnet = "${primaryInterface}.4000";
  vrrpInstanceName = "VI_1";
  vrrpRouterId = 51;
  vrrpState = "BACKUP";
  virtualIpAddress = "178.63.143.219/32";

  # Kubelet configuration paths
  kubeletBootstrapConf = "${k8sEtcDir}/bootstrap-kubelet.conf";
  kubeletConf = "${k8sEtcDir}/kubelet.conf";
  kubeletConfigYaml = "/var/lib/kubelet/config.yaml";
  kubeletConfigDir = "${k8sEtcDir}/kubelet/config.d";
}
