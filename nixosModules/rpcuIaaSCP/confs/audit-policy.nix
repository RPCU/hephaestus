# Kubernetes audit policy for API server logging
{ }:
{
  "kubernetes/audit/policy.yaml".text = ''
    apiVersion: audit.k8s.io/v1
    kind: Policy
    omitStages:
      - "RequestReceived"
      - "ResponseStarted"
      - "ResponseComplete"
    rules:
      # Capture 'create' and 'delete' operations for all resources
      - level: Metadata
        verbs: ["create", "delete"]
      # Explicitly drop all other operations (get, list, watch, patch, update)
      - level: None
  '';
}
