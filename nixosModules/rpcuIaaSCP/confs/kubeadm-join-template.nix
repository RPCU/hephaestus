# Kubeadm join configuration template (cluster-specific)
{
  apiserverVip,
  cfg,
}:
{
  "kubernetes/kubeadm/join.yaml.tpl".text = ''
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: JoinConfiguration
    nodeRegistration:
      taints: []
    controlPlane:
      localAPIEndpoint:
        advertiseAddress: '${cfg.cluster.privateAddress}'
        bindPort: 6443
      certificateKey: '__CERTIFICATE_KEY__'
    discovery:
      bootstrapToken:
        token: '__TOKEN__'
        unsafeSkipCAVerification: true
        apiServerEndpoint: "${apiserverVip}:6443"
  '';
}
