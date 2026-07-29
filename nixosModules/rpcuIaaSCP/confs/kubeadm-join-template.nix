# Kubeadm join configuration template (cluster-specific)
{
  apiserverVip,
  cfg,
}:
{
  # v1beta4 to match kubeadm-bootstrap.nix (v1beta3 is deprecated in k8s 1.36).
  "kubernetes/kubeadm/join.yaml.tpl".text = ''
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: JoinConfiguration
    nodeRegistration:
      taints: []
    controlPlane:
      localAPIEndpoint:
        advertiseAddress: '${cfg.privateAddress}'
        bindPort: 6443
      certificateKey: '__CERTIFICATE_KEY__'
    discovery:
      bootstrapToken:
        token: '__TOKEN__'
        unsafeSkipCAVerification: true
        apiServerEndpoint: "${apiserverVip}:6443"
  '';
}
