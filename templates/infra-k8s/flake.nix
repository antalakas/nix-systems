{
  description = "Infrastructure/K8s project with pinned tool versions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # AWS
            awscli2
            
            # Kubernetes (pinned versions if needed)
            kubectl              # or: kubectl_1_30
            kubernetes-helm      # or: helm_3_14
            kustomize
            argocd
            
            # Terraform
            opentofu             # or: terraform
            
            # Utilities
            jq
            yq-go
          ];

          shellHook = ''
            echo "Infra dev environment"
            
            # Set project-specific kubeconfig if needed
            # export KUBECONFIG="$HOME/.kube/my-cluster.yaml"
            
            # Or switch context
            # kubectx my-context 2>/dev/null || true
          '';
        };
      });
}
