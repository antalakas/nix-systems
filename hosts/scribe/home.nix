# User configuration for `scribe`, the portable one.
#
# Unlike forge and nuc this host has a screen, so it imports the two desktop
# modules as well as the shared CLI baseline. Unlike the main laptop it is a
# client rather than a workshop: the applications are a terminal, a browser and
# Zed, and everything heavier happens on forge over the tailnet.

{ config, pkgs, lib, ... }:

{
  imports = [
    ../../home/common.nix
    ../../home/alacritty.nix
    ../../home/ssh-tint.nix
    ../../home/niri-desktop.nix
  ];

  # Set at install, to the release this host was installed from. See the
  # system.stateVersion note in default.nix — the same caveat applies.
  home.stateVersion = "26.11";

  programs.zsh.initContent = ''
    # NixOS aliases. No --impure: like forge and nuc, and unlike the main
    # laptop, this host's config has no out-of-tree imports, so it evaluates
    # purely.
    alias nrs='sudo nixos-rebuild switch --flake /etc/nixos#scribe'
    alias nrb='sudo nixos-rebuild boot --flake /etc/nixos#scribe'
    alias nrt='sudo nixos-rebuild test --flake /etc/nixos#scribe'
  '';

  # Both halves of the tint, which no other host needs. This machine is one you
  # sit at *and* one that is reachable over the tailnet:
  #
  #   enable      — paints the client's terminal when someone ssh's in here.
  #   clientReset — clears a tint left behind when *this* machine's ssh session
  #                 to forge or nuc drops without running its own exit hook.
  #
  # Amber-brown for the background, keeping to the module's advice to separate
  # hosts by hue at a similar brightness: forge is blue #0f2438, nuc green
  # #0f2a1e, the laptop's own rose_pine #191724 a dark purple. The matching
  # focus-ring rule is green #9ece6a, added by hand to all three profiles under
  # dotfiles/niri/ — the ring is a separate scale from the background and only
  # has to be unmistakable against the other rings.
  my.sshTint = {
    enable = true;
    label = "scribe";
    background = "#33210f";
    clientReset = true;
  };

  # Same theme as the main laptop, on purpose: the two are meant to feel like
  # one environment, and you can tell which laptop you are holding without help
  # from the colour scheme. The remote hosts are the ones that need telling
  # apart, and the tint above is what does it.
  my.alacritty.theme = "rose_pine";

  # The niri profile. A single file rather than the symlink-and-switcher
  # arrangement in hosts/nixos/home.nix, because that exists to flip between
  # the home and office monitor rigs and this machine has one panel. If it ever
  # acquires a dock, add a second profile and dotfiles/niri/switch-profile.sh
  # back alongside it.
  home.file.".config/niri/config.kdl".source = ../../dotfiles/niri/config-mobile.kdl;

  # Zed remote development, client side. This is the point of the machine: the
  # editor runs locally on the panel in front of you and the filesystem,
  # language servers and builds are all on forge.
  #
  # The server half is hosts/forge/home.nix, which installs the nix-built
  # remote server into ~/.zed_server. No such entry here — nothing Zed-remotes
  # *into* this laptop.
  #
  # Client and server versions must match exactly. Both come from this flake's
  # nixpkgs, so after `nix flake update` rebuild both hosts, not just one. See
  # docs/forge-install.md §10.
  #
  # The tailnet FQDN rather than the short name: the router answers short names
  # out of its own DHCP records before MagicDNS is consulted, and those records
  # outlive the machine that created them (docs/nuc-install.md §6 hit exactly
  # this). It also means this does not depend on a hand-written ~/.ssh/config
  # alias existing.
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor-fhs;
    userSettings = {
      markdown_preview.limit_content_width = false;

      # `projects` is deliberately empty on both. Zed appends every remote path
      # you open, but the activation merge replaces arrays wholesale rather
      # than merging them, so that list is reset on each `nrs`. Connecting is
      # unaffected — only the picker's recent-paths list.
      ssh_connections = [
        {
          host = "forge.taile6c0b.ts.net";
          username = "andreas";
          nickname = "forge";
          projects = [ ];
        }
        {
          host = "nuc.taile6c0b.ts.net";
          username = "andreas";
          nickname = "nuc";
          projects = [ ];
        }
      ];
    };
  };

  # Note on what comes from home/common.nix and is *not* expected to be used
  # here: the Claude Code sandbox (~/.local/bin/claude-sandbox, the Dockerfile
  # and refs.conf). It is installed on every host because it needs nothing but
  # Docker, and it will work on this one — but the reason this laptop exists is
  # to drive the sandbox running on forge, and hosts/scribe/default.nix leaves
  # dockerd socket-activated on that assumption. Running it locally is a
  # fallback, not the path.
}
