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

    # Declarative disk partitioning, used to install `forge` from
    # hosts/forge/disko.nix rather than by hand at the shell.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets committed to this repo encrypted, decrypted at activation with a
    # key derived from the host's SSH host key. See .sops.yaml.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
        ./hosts/nixos
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
              ./hosts/nixos/home.nix
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

    # forge — headless dev box. Unlike `nixos` above, this one evaluates purely:
    # it has no out-of-tree imports, so it needs no `--impure`.
    nixosConfigurations.forge = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/forge
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.andreas = {
            imports = [
              nixvim.homeModules.nixvim
              ./hosts/forge/home.nix
            ];
            programs.nixvim.nixpkgs.source = nixpkgs;
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };

    # nuc — headless always-on box, same shape as forge and likewise pure.
    # Neither disko nor sops-nix is wired in: this host has no disko.nix and no
    # secrets file yet. Add the module here at the same time as the file, not
    # before. hosts/nuc/hardware-configuration.nix is still a placeholder that
    # throws, so this output does not evaluate until it is replaced.
    nixosConfigurations.nuc = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/nuc

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.andreas = {
            imports = [
              nixvim.homeModules.nixvim
              ./hosts/nuc/home.nix
            ];
            programs.nixvim.nixpkgs.source = nixpkgs;
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
