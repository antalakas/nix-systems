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

    # Tint the client's terminal for the length of an ssh session, so a nuc
    # shell is visibly neither a laptop one nor a forge one. This is forge's
    # arrangement with two values changed — hosts/forge/home.nix explains why
    # the repainting has to happen at the far end, why it is guarded on
    # SSH_CONNECTION and interactive, and why the title hooks replace
    # oh-my-zsh's rather than wrapping them. None of that is repeated here.
    #
    # Green rather than forge's #0f2438, at deliberately the same brightness:
    # the two headless boxes should be told apart by hue, not by which one is
    # darker. Both are far enough from the laptop's rose_pine #191724 that a
    # glance is enough.
    #
    # The laptop needs nothing for this. Its OSC 111 reset in
    # hosts/nixos/home.nix runs on every local prompt and names no host, so it
    # already un-tints the window after a connection here drops.
    if [[ -o interactive && -n $SSH_CONNECTION ]]; then
      printf '\033]11;#0f2a1e\a'
      _nuc_reset_bg() { printf '\033]111\a'; }
      autoload -Uz add-zsh-hook
      add-zsh-hook zshexit _nuc_reset_bg

      # The second, independent cue, for when OSC 11 cannot get through — see
      # the matching window-rule in dotfiles/niri/config-{home,office}.kdl.
      DISABLE_AUTO_TITLE=true
      _nuc_title_idle() { print -Pn '\033]0;nuc: %~\a'; }
      _nuc_title_cmd() { print -Pn '\033]0;nuc: '; print -rn -- "$1"; print -n '\a'; }
      add-zsh-hook precmd _nuc_title_idle
      add-zsh-hook preexec _nuc_title_cmd
    fi
  '';
}
