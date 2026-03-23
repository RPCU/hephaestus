# overlays/kubernetes.nix
final: prev: {
  # This attribute is a function that takes the configuration (specifically, the customNixOSModules.kubernetes.version)
  # and returns the versioned kubernetes packages.
  getKubernetesPackages =
    { config }:
    let
      cfg = config.customNixOSModules;
      sources = import ../npins; # Assuming npins is at the project root

      getNixpkgsForK8sVersion =
        k8sVersion:
        let
          nixpkgsSource =
            sources."nixpkgs-k8s-${k8sVersion}"
              or (throw "Nixpkgs source for Kubernetes version ${k8sVersion} not found in npins. Please add an entry like 'nixpkgs-k8s-${k8sVersion}' to your sources.json.");
        in
        import nixpkgsSource {
          inherit (prev.stdenv.hostPlatform) system;
          config = { inherit (config.nixpkgs.config) allowUnfree allowUnfreePredicate; };
        };

      nixpkgsForKubeadm = getNixpkgsForK8sVersion cfg.kubernetes.version.kubeadm;
      nixpkgsForKubelet = getNixpkgsForK8sVersion cfg.kubernetes.version.kubelet;
    in
    {
      kubernetes_kubeadm = nixpkgsForKubeadm.kubernetes;
      kubernetes_kubelet = nixpkgsForKubelet.kubernetes;
    };
}
