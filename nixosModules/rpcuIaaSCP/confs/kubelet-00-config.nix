# Common kubelet configuration (all nodes)
{ }:
{
  "kubernetes/kubelet/config.d/00-config.conf".text = ''
    kind: KubeletConfiguration
    apiVersion: kubelet.config.k8s.io/v1beta1
    maxPods: 110
    rotateCertificates: true
    imageMaximumGCAge: 720h
    imageGCLowThresholdPercent: 70
    imageGCHighThresholdPercent: 85
    featureGates:
      SidecarContainers: true
    # cgroupDriver: systemd
    # systemReservedCgroup: /system.slice
    # enforceNodeAllocatable:
    #   - pods
    #   - system-reserved
    # systemReserved:
    #   cpu: "1"
    #   memory: "4Gi"
    #   ephemeral-storage: "2Gi"
    # evictionHard:
    #   memory.available: "500Mi"
    #   nodefs.available: "10%"
    #   imagefs.available: "15%"
  '';
}
