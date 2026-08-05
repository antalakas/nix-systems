# User configuration for `forge`, the headless dev box.

{ config, pkgs, lib, ... }:

{
  imports = [ ../../home/common.nix ];

  home.stateVersion = "26.11";

  # Zed remote development.
  #
  # Zed's client pushes a `zed-remote-server-stable-<version>` binary to
  # ~/.zed_server on the host, which will not run on NixOS — it is a generic
  # dynamically linked binary and there is no /lib64/ld-linux-x86-64.so.2.
  # Installing the nix-built server sidesteps that entirely.
  #
  # Client and server versions must match exactly or the connection is refused.
  # Both come from this flake's nixpkgs, so after `nix flake update` rebuild
  # both hosts, not just one. If they do drift, set
  # "upload_binary_over_ssh": true in the laptop's Zed settings as a stopgap.
  #
  # `recursive = true` symlinks the individual binaries instead of the
  # directory, which keeps ~/.zed_server writable — Zed wants to manage it.
  home.file = lib.mkIf (pkgs.zed-editor ? remote_server) {
    ".zed_server" = {
      source = "${pkgs.zed-editor.remote_server}/bin";
      recursive = true;
    };
  };

  programs.zsh.initContent = ''
    # NixOS aliases. No --impure here: unlike the laptop, this host's config
    # has no out-of-tree imports, so it evaluates purely.
    alias nrs='sudo nixos-rebuild switch --flake /etc/nixos#forge'
    alias nrb='sudo nixos-rebuild boot --flake /etc/nixos#forge'
    alias nrt='sudo nixos-rebuild test --flake /etc/nixos#forge'
  '';
}
