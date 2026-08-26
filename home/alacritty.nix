# Alacritty, shared by every graphical host. Everything here is host-agnostic
# except the colour scheme: each host sets `my.alacritty.theme` in its own
# hosts/<host>/home.nix. Headless hosts (forge) never import this — alacritty
# runs on the machine you are sitting at, not the one you ssh into.

{ config, pkgs, lib, ... }:

let
  cfg = config.my.alacritty;

  alacrittyThemes = pkgs.fetchFromGitHub {
    owner = "alacritty";
    repo = "alacritty-theme";
    rev = "02ed0a1826d008885c0cd4589c9eff892773a62a";
    hash = "sha256-ljTdsfd/bClvnr2DlndEreNuLZ705wo+XSCvkUBVw8Y=";
  };
in
{
  options.my.alacritty.theme = lib.mkOption {
    type = lib.types.str;
    default = "rose_pine";
    example = "tokyo_night_storm";
    description = ''
      Theme to import from the alacritty/alacritty-theme repo, named after its
      file under themes/ (without the .toml). Good options: tokyo_night_storm,
      catppuccin_mocha, kanagawa_wave, nightfox, rose_pine, github_dark,
      gruvbox_dark. A name with no matching file fails the build at activation,
      when the import path does not exist.
    '';
  };

  config = {
    programs.alacritty = {
      enable = true;
      settings = {
        general.import = [ "${alacrittyThemes}/themes/${cfg.theme}.toml" ];
        terminal.shell.program = "${pkgs.zsh}/bin/zsh";

        window = {
          padding = { x = 12; y = 12; };
          decorations = "None";
          opacity = 0.95;
        };

        scrolling = {
          history = 10000;
          multiplier = 3;
        };

        font = {
          size = 12.0;
          normal = {
            family = "Iosevka Nerd Font";
            style = "Regular";
          };
          bold.family = "Iosevka Nerd Font";
          italic.family = "Iosevka Nerd Font";
        };

        cursor = {
          style = {
            shape = "Beam";
            blinking = "On";
          };
          blink_interval = 750;
        };

        env = {
          TERM = "xterm-256color";
        };
      };
    };

    # Force overwrite Alacritty config (prevent backup collisions)
    xdg.configFile."alacritty/alacritty.toml".force = true;
  };
}
