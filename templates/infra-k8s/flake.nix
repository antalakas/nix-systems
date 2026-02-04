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
            # AWS profile for this project (customize)
            export AWS_PROFILE=your-profile-name
            
            # Auto-switch to project's k8s context (customize)
            kubectx your-context 2>/dev/null || true
            
            echo "📦 Infra dev environment"
            echo "  AWS Profile: $AWS_PROFILE"
            echo "  K8s Context: $(kubectl config current-context 2>/dev/null || echo 'none')"
            echo ""
            echo "💡 Use './avx' for aws-vault shell or './avx <command>' to run commands"
          '';
        };
      });
}
