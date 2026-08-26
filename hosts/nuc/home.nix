# User configuration for `nuc`, the headless always-on box.
#
# home/alacritty.nix is deliberately not imported: this host has no display, so
# a terminal config here would be written and never read. A shell on this box
# is painted by whatever terminal you sshed in from.

{ config, pkgs, lib, ... }:

{
  imports = [ ../../home/common.nix ];

  # Set at install, to the release this host was installed from. See the
  # system.stateVersion note in default.nix — the same caveat applies.
  home.stateVersion = "26.11";

  programs.zsh.initContent = ''
    # NixOS aliases. No --impure here: like forge and unlike the laptop, this
    # host's config has no out-of-tree imports, so it evaluates purely.
    alias nrs='sudo nixos-rebuild switch --flake /etc/nixos#nuc'
    alias nrb='sudo nixos-rebuild boot --flake /etc/nixos#nuc'
    alias nrt='sudo nixos-rebuild test --flake /etc/nixos#nuc'
  '';
}
