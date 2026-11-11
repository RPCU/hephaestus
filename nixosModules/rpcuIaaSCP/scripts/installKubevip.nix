{
  pkgs,
  k8sAdminConf,
  k8sSuperAdminConf,
  kubevipImage,
  primaryInterface,
  apiserverVip,
  k8sManifestsDir,
}:
pkgs.writeShellScriptBin "installKubevip" ''
  set -euo pipefail

  # Determine which config to use. Prefer admin.conf if it exists,
  # but fall back to super-admin.conf for initial bootstrap.
  K8S_CONFIG="${k8sAdminConf}"
  if [[ ! -f "$K8S_CONFIG" ]]; then
    K8S_CONFIG="${k8sSuperAdminConf}"
  fi

  echo "Using Kubernetes config: $K8S_CONFIG" >&2

  # Pull and configure kube-vip
  ctr image pull ${kubevipImage}
  kubevip="ctr run --rm --net-host ${kubevipImage} vip /kube-vip"

  # Control-plane VIP only, no --services: Cilium LB-IPAM + L2 announcements
  # own the LoadBalancer IPs (argus infrastructure/cilium). kube-vip's services
  # mode announced them a second time and bound each one as a local /32 on the
  # leader, so traffic forwarded to it from another interface (NetBird's wt0,
  # which isn't a Cilium device) hit the host stack instead of the service:
  # DNS through 10.0.0.241 answered "connection refused" whenever NetBird
  # routed 10.0.0.0/24 via the kube-vip leader.
  $kubevip manifest pod \
    --interface ${primaryInterface}.4000 \
    --address ${apiserverVip} \
    --controlplane --arp --leaderElection \
    --k8sConfigPath="$K8S_CONFIG" | tee ${k8sManifestsDir}/kube-vip.yaml
''
