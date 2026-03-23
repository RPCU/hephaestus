{
  pkgs,
  k8sBootstrapYaml,
  k8sAdminConf,
  configureKubectl,
  applyNodeLabels,
}:
pkgs.writeShellScriptBin "initKubeadm" ''
  set -euo pipefail

  # Display help menu
  if [[ "''${@:-}" == *"--help"* || "''${@:-}" == *"-h"* ]]; then
    cat << 'HELP'
  Usage: initKubeadm

  Description:
    - Deploys kubevip manifests for HA
    - Initializes the Kubernetes cluster using bootstrap.yaml
    - Filters output to display the join token and certificate key
  HELP
    exit 0
  fi

  # Setup static pods for kube-vip
  installKubevip

  # Initialize cluster and extract credentials
  echo "Initializing cluster (this may take a minute)..." >&2
  OUTPUT=$(kubeadm init --config ${k8sBootstrapYaml} --upload-certs)

  # Regenerate kube-vip manifest with admin.conf
  installKubevip

  # Extract join credentials from output
  TOKEN=$(echo "$OUTPUT" | grep -oP '(?<=--token )[^ ]+' | head -n 1)
  CERT_KEY=$(echo "$OUTPUT" | grep -oP '(?<=--certificate-key )[^ ]+' | head -n 1)

  # Configure kubectl access
  ${configureKubectl}

  # Display cluster initialization summary
  echo "--------------------------------------------------"
  echo "CLUSTER INITIALIZED SUCCESSFULLY"
  echo "--------------------------------------------------"
  echo ""

  # Apply node labels and show nodes
  echo "---"
  ${applyNodeLabels}
  echo "---"
  echo ""

  # Display join command if credentials extracted successfully
  if [[ -n "$TOKEN" && -n "$CERT_KEY" ]]; then
    echo "To join another Control Plane node, run:"
    echo ""
    echo "joinCPKubeadm $TOKEN $CERT_KEY"
  else
    echo "Error: Could not extract join credentials from kubeadm output."
    exit 1
  fi
''
