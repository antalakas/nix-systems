{
  description = "NixOS configuration with Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management (services.flatpak.packages);
    # ?ref=latest tracks the latest stable tag per the nix-flatpak README.
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    # Pinned to the last rev whose ollama-cuda we already built locally —
    # ollama-cuda is unfree (never binary-cached), so tracking unstable means
    # a long local CUDA compile on every bump. See services.ollama in
    # configuration.nix; drop when nixpkgs#545542 lands and a rebuild is ok.
    nixpkgs-ollama.url = "github:NixOS/nixpkgs/549bd84d6279f9852cae6225e372cc67fb91a4c1";
  };

  outputs = { self, nixpkgs, home-manager, nixvim, nix-flatpak, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nix-flatpak.nixosModules.nix-flatpak

        # Home Manager as NixOS module
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.andreas = {
            imports = [
              nixvim.homeModules.nixvim
              ./home.nix
            ];
            # Nixvim evaluates its own nixpkgs instance; we deliberately point
            # it at the system nixpkgs (matching the `follows` in inputs),
            # which also silences nixvim's pin-mismatch warning.
            programs.nixvim.nixpkgs.source = nixpkgs;
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
