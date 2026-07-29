# Kubeadm bootstrap configuration for cluster initialization
{
  lib,
  cfg,
  kubeadmVersion,
  apiserverVip,
  podCidr,
  allNodeIps,
}:
{
  # NOTE: kubeadm API is v1beta4 (required for `encryptionAlgorithm`, which is
  # not present in v1beta3). v1beta4 also changed `apiServer.extraArgs` from a
  # map to a list of {name, value} pairs — hence the list form below.
  "kubernetes/kubeadm/bootstrap.yaml".text = ''
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: ClusterConfiguration
    clusterName: 'openstack'
    # ECDSA P-256 control-plane keys/certs instead of the kubeadm default
    # RSA-2048. The dominant baseline CPU cost on a kube-apiserver at low
    # request volume is the per-connection TLS handshake (asymmetric crypto);
    # an ECDSA-P256 handshake is ~5-10x cheaper server-side than RSA-2048.
    # On these hyperconverged baremetal nodes (apiserver competes with Ceph +
    # nova VMs for CPU) that handshake cost is a meaningful share of apiserver
    # CPU. NOTE: this only affects certs generated at `kubeadm init` / cert
    # renewal — the already-running cluster keeps its RSA certs until they are
    # rotated (`kubeadm certs renew all` on each control-plane node, then
    # restart the control-plane static pods) or the node is re-bootstrapped.
    encryptionAlgorithm: 'ECDSA-P256'
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
        ${lib.concatMapStringsSep "\n    " (ip: "- '${ip}'") allNodeIps}
      extraArgs:
        - name: enable-admission-plugins
          value: DefaultTolerationSeconds
        - name: audit-policy-file
          value: '/etc/kubernetes/audit/policy.yaml'
        - name: audit-log-path
          value: '/var/log/kubernetes_audit.log'
        - name: audit-log-maxsize
          value: '100'
        - name: audit-log-maxbackup
          value: '10'
        - name: audit-log-mode
          value: 'batch'
        - name: audit-log-batch-max-size
          value: '5'
      extraVolumes:
        - name: auditpolicy
          hostPath: /etc/kubernetes/audit/policy.yaml
          mountPath: /etc/kubernetes/audit/policy.yaml
    ---
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: InitConfiguration
    skipPhases:
      - addon/kube-proxy
    localAPIEndpoint:
      advertiseAddress: '${cfg.privateAddress}'
      bindPort: 6443
    nodeRegistration:
      taints: []
  '';
}
