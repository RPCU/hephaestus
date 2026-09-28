# Common kubelet configuration (all nodes)
{ cfg }:
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
    cgroupDriver: systemd
    systemReservedCgroup: /system.slice
    enforceNodeAllocatable:
      - pods
    # Host + OpenStack VM share (qemu lives in machine.slice, invisible to
    # the scheduler) — see the rpcuIaaSCP `hostPartition` option.
    systemReserved:
      cpu: "${cfg.hostPartition.systemReservedCpu}"
      memory: "${cfg.hostPartition.systemReservedMemory}"
      ephemeral-storage: "10Gi"
    evictionHard:
      memory.available: "1Gi"
      nodefs.available: "10%"
      imagefs.available: "15%"
  '';
}
