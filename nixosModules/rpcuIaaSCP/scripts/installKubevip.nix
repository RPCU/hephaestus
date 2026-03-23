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

  $kubevip manifest pod \
    --interface ${primaryInterface}.4000 \
    --address ${apiserverVip} \
    --controlplane --services --arp --leaderElection \
    --k8sConfigPath="$K8S_CONFIG" | tee ${k8sManifestsDir}/kube-vip.yaml
''
