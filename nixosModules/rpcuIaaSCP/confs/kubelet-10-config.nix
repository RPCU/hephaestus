# Cluster-specific kubelet configuration (cluster nodes only)
{ cfg }:
{
  "kubernetes/kubelet/config.d/10-config.conf".text = ''
    kind: KubeletConfiguration
    apiVersion: kubelet.config.k8s.io/v1beta1
    address: "${cfg.privateAddress}"
  '';
}
