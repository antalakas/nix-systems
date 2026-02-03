{
  description = "Python project with pixi environment management";

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
            # Pixi handles Python environment via pixi.toml
            pixi
            
            # Optional: useful dev tools
            # pre-commit
            # ruff
          ];

          shellHook = ''
            echo "Python/Pixi dev environment"
            echo "Run 'pixi init' to initialize, then 'pixi add <package>' to add deps"
            echo ""
            
            # Auto-activate pixi environment if it exists
            if [ -f pixi.toml ]; then
              eval "$(pixi shell-hook)"
            fi
          '';
        };
      });
}
