# Repainting the client's terminal for the length of an ssh session, so a shell
# on a remote box is never mistaken for a local one. Imported by the headless
# hosts, which each set `my.sshTint` in their own hosts/<host>/home.nix.
#
# This is home/alacritty.nix's mirror image. That module configures the terminal
# on machines you sit at; a headless host never runs one, so the only thing it
# can change is the terminal at the far end of the connection — which it does by
# writing escape sequences at it rather than by configuring anything.
#
# Two halves, and they are independent. `enable` is the *remote* half, for a
# host you ssh into. `clientReset` is the *local* half, for a host you ssh out
# of — it undoes a tint that a dropped connection never got to undo itself. A
# headless box wants only the first; the main laptop wants only the second (and
# still carries its own inline copy, in hosts/nixos/home.nix, predating this
# option); scribe is the first host that is both, and sets both.

{ config, pkgs, lib, ... }:

let
  cfg = config.my.sshTint;
in
{
  options.my.sshTint = {
    enable = lib.mkEnableOption "repainting the client terminal during ssh sessions";

    label = lib.mkOption {
      type = lib.types.str;
      example = "forge";
      description = ''
        Prefix for the client terminal's window title, written as
        "<label>: <cwd>". niri matches on it to colour the focus ring, so a new
        host also needs a window-rule added by hand to *every* profile under
        dotfiles/niri/ — config-home.kdl, config-office.kdl, config-igo.kdl
        and config-mobile.kdl — because niri's KDL has no include directive
        and nothing here generates those.
      '';
    };

    background = lib.mkOption {
      type = lib.types.str;
      example = "#0f2438";
      description = ''
        Background to repaint the client terminal with. A raw hex value rather
        than a theme name: home/alacritty.nix does not come into it, because
        the terminal being repainted belongs to another machine entirely.

        Choose by hue, not by brightness. Hosts are told apart far more reliably
        by colour than by which one is darker, so keep new values at roughly the
        brightness of the existing ones rather than reaching for a darker shade.
        Stay well clear of the laptop's rose_pine #191724 — tokyo_night's
        #1a1b26 is within a few points of it and the two are indistinguishable
        in practice, which defeats the whole point.
      '';
    };

    clientReset = lib.mkEnableOption ''
      resetting this terminal's background at every local prompt, undoing a
      tint left behind by a remote host.

      Independent of `enable` above: this is what a machine you sit *at* wants,
      not one you ssh into. The two live in one module only because they are
      the two ends of a single mechanism
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      programs.zsh.initContent = ''
        # Tint this terminal for the length of the ssh session (home/ssh-tint.nix).
        # OSC 11 sets the background, OSC 111 restores the theme's own.
        #
        # Guarded on SSH_CONNECTION so the host's physical console — a Linux VT
        # that does not speak OSC 11 — is left alone, and on interactive so that
        # `ssh <host> <cmd>`, scp and rsync repaint nothing. zshexit restores the
        # background on a clean logout; a dropped connection never gets to run it,
        # which is what `clientReset` below is for.
        if [[ -o interactive && -n $SSH_CONNECTION ]]; then
          printf '\033]11;${cfg.background}\a'
          _ssh_tint_reset_bg() { printf '\033]111\a'; }
          autoload -Uz add-zsh-hook
          add-zsh-hook zshexit _ssh_tint_reset_bg

          # A second, independent cue, for when the first cannot get through: a
          # multiplexer that does not forward OSC 11, or a terminal that ignores
          # it, leaves the background exactly as it was. A window title always
          # arrives, so prefix it and let niri colour the focus ring off that.
          #
          # oh-my-zsh retitles to the bare command line while one runs, which
          # would drop the prefix and flip the ring back for the length of a
          # build, so replace its hooks rather than wrap them.
          DISABLE_AUTO_TITLE=true
          _ssh_tint_title_idle() { print -Pn '\033]0;${cfg.label}: %~\a'; }
          _ssh_tint_title_cmd() { print -Pn '\033]0;${cfg.label}: '; print -rn -- "$1"; print -n '\a'; }
          add-zsh-hook precmd _ssh_tint_title_idle
          add-zsh-hook preexec _ssh_tint_title_cmd
        fi
      '';
    })

    (lib.mkIf cfg.clientReset {
      programs.zsh.initContent = ''
        # Undo a remote shell's tint. The `enable` half above repaints this
        # terminal over OSC 11 for the length of an ssh session and restores it
        # from zshexit, but a dropped connection never runs that hook and would
        # strand the window tinted until you reset it by hand. Host-agnostic on
        # purpose: every host that enables the tint is covered here without
        # naming any of them.
        #
        # A precmd rather than a one-shot at startup, because the shell that ran
        # `ssh <host>` is still alive underneath the connection: when it dies you
        # are returned to that shell, which never re-sources .zshrc. Its next
        # prompt is the first local code to run, so that is where the reset
        # belongs. OSC 111 is a no-op when nothing has been tinted, and one write
        # per prompt does not register.
        #
        # Skipped inside tmux, where it would be pointless rather than wrong: a
        # multiplexer that will not forward the tint out will not forward the
        # reset either, so neither ever reaches the terminal.
        if [[ -o interactive && -z $SSH_CONNECTION && -z $TMUX ]]; then
          autoload -Uz add-zsh-hook
          _reset_term_bg() { printf '\033]111\a'; }
          add-zsh-hook precmd _reset_term_bg
        fi
      '';
    })
  ];
}
