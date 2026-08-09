# Common kubelet configuration (all nodes)
{ cfg }:
let
  isLucy = cfg.privateAddress == "10.0.0.2";
in
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
    systemReserved:
      cpu: "${if isLucy then "2" else "1"}"
      memory: "${if isLucy then "20Gi" else "4Gi"}"
      ephemeral-storage: "10Gi"
    evictionHard:
      memory.available: "1Gi"
      nodefs.available: "10%"
      imagefs.available: "15%"
  '';
}
