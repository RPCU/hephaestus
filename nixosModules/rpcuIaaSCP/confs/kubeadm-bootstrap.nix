# Kubeadm bootstrap configuration for cluster initialization
{
  lib,
  cfg,
  kubeadmVersion,
  apiserverVip,
  podCidr,
}:
{
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
        ${lib.concatMapStringsSep "\n        " (ip: "- '${ip}'") cfg.cluster.allNodeIps}
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
      advertiseAddress: '${cfg.cluster.privateAddress}'
      bindPort: 6443
       nodeRegistration:
         taints: []
  '';
}
