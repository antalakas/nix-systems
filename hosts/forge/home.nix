# User configuration for `forge`, the headless dev box.

{ config, pkgs, lib, ... }:

{
  imports = [ ../../home/common.nix ];

  home.stateVersion = "26.11";

  # The mempalace miner's CPU cap inside the Claude sandbox. The image defaults
  # to 6, a number chosen for the laptop's 22 cores after the miner pegged 15 of
  # them; this box has 24, so half is both a real increase and enough headroom
  # left for a build or a kind cluster running alongside. claude-sandbox
  # forwards the variable only when the host sets one — see docs/forge-install.md §8.
  home.sessionVariables.MEMPALACE_MINE_CPUS = "12";

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

    # Tint the client's terminal for the length of an ssh session, so a forge
    # shell is visibly not a laptop one. This box is headless — it does not
    # import home/alacritty.nix and never runs a terminal — so the only thing
    # that can change what you see is the terminal at the far end, repainted
    # with OSC 11 (set background) and OSC 111 (reset to the theme's own).
    #
    # The colour is deliberately not tokyo_night's #1a1b26: that is within a
    # few points of the laptop's rose_pine #191724 and the two would look
    # identical, which defeats the point. It is a raw value, not a theme name,
    # so change it here rather than in home/alacritty.nix.
    #
    # Guarded on SSH_CONNECTION so this host's physical console — a Linux VT
    # that does not speak OSC 11 — is left alone, and on interactive so that
    # `ssh forge <cmd>`, scp and rsync do not repaint anything. zshexit
    # restores the background on a clean logout; a dropped connection never
    # gets to run it, in which case `printf '\033]111\a'` locally undoes it.
    if [[ -o interactive && -n $SSH_CONNECTION ]]; then
      printf '\033]11;#0f2438\a'
      _forge_reset_bg() { printf '\033]111\a'; }
      autoload -Uz add-zsh-hook
      add-zsh-hook zshexit _forge_reset_bg
    fi
  '';
}
