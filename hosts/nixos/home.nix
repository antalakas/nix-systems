{ config, pkgs, lib, ... }:

let
  # Change this to switch Alacritty themes.
  # Good options from alacritty-theme:
  # - tokyo_night_storm
  # - catppuccin_mocha
  # - kanagawa_wave
  # - nightfox
  # - rose_pine
  # - github_dark
  # - gruvbox_dark
  alacrittyTheme = "rose_pine";
  alacrittyThemes = pkgs.fetchFromGitHub {
    owner = "alacritty";
    repo = "alacritty-theme";
    rev = "02ed0a1826d008885c0cd4589c9eff892773a62a";
    hash = "sha256-ljTdsfd/bClvnr2DlndEreNuLZ705wo+XSCvkUBVw8Y=";
  };
in
{
  # The CLI toolchain, git, zsh, tmux, direnv, neovim and the Claude Code
  # sandbox come from home/common.nix. What is left here is the desktop.
  imports = [ ../../home/common.nix ];

  # This should match your NixOS version
  home.stateVersion = "24.11";

  # ─────────────────────────────────────────────────────────────
  # User Packages (installed for this user only)
  # ─────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    sox        # audio processing CLI

    # Applications
    _1password-gui    # 1Password password manager
    sublime4          # Sublime Text editor
    xournalpp         # PDF annotation and signature tool
    foliate           # EPUB ebook reader
    pinta             # Quick image editor for cropping and format conversion
    gthumb            # Image viewer and organizer with basic editing
    obs-studio        # Screen recording and streaming
    wf-recorder       # Lightweight CLI screen recorder for Wayland
    mpv               # Lightweight video player
    ffmpeg            # Video/audio tools (ffmpeg, ffprobe, ffplay)
    dbeaver-bin        # SQL editor and database manager
    # zed-editor-fhs is installed by programs.zed-editor below
    zoom-us            # Zoom video conferencing
    teams-for-linux    # Microsoft Teams (community Electron wrapper)
    klavaro            # Touch typing tutor
    oda-file-converter # Convert between .dwg and .dxf formats
    libredwg           # Free implementation of the DWG file format
    
    # Wallpaper
    swaybg     # Wayland wallpaper tool
    
    # Notifications
    mako       # Wayland notification daemon
    libnotify  # provides notify-send command
    papirus-icon-theme  # Beautiful icon theme for notifications
  ];

  # ─────────────────────────────────────────────────────────────
  # Zsh — the shared parts (history, oh-my-zsh, aliases) are in
  # home/common.nix; only the rebuild aliases are host-specific.
  # ─────────────────────────────────────────────────────────────
  programs.zsh.initContent = ''
    # NixOS aliases. --impure because this host imports langfuse.nix from
    # outside the repo (see hosts/nixos/default.nix).
    alias nrs='sudo nixos-rebuild switch --flake /etc/nixos --impure'
    alias nrb='sudo nixos-rebuild boot --flake /etc/nixos --impure'
    alias nrt='sudo nixos-rebuild test --flake /etc/nixos --impure'
  '';

  # ─────────────────────────────────────────────────────────────
  # XDG Config Files
  # ─────────────────────────────────────────────────────────────
  xdg.configFile = {
    # Force overwrite Alacritty config (prevent backup collisions)
    "alacritty/alacritty.toml".force = true;
  };

  # ─────────────────────────────────────────────────────────────
  # Zed
  # ─────────────────────────────────────────────────────────────
  # mutableUserSettings defaults to true, so settings.json stays writable and
  # Zed's own UI keeps working — activation merges these keys over whatever
  # Zed wrote (`$dynamic * $static`, so these win on every `nrs`). Keeping
  # zed-editor-fhs as the package preserves the FHS extension installs.
  # defaultEditor is left off so nixvim remains $EDITOR.
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor-fhs;
    userSettings = {
      # By default the preview caps content at max_width (800px) and centres
      # it, leaving a narrow strip on a wide screen. false renders edge to
      # edge; if that turns out too wide for comfortable prose, drop this key
      # and set `max_width` to something like 1400 instead.
      markdown_preview.limit_content_width = false;
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Default applications (MIME associations)
  # ─────────────────────────────────────────────────────────────
  # Note: this makes ~/.config/mimeapps.list a read-only store symlink, so
  # "Open with → always use this" in a GUI file manager stops sticking —
  # add associations here instead.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Zed's desktop entry only advertises text/plain, so .md would otherwise
      # fall to whichever text handler wins. Naming it explicitly keeps
      # double-click on a .md landing in Zed (ctrl-shift-v for the preview).
      "text/markdown" = "dev.zed.Zed.desktop";
      "text/x-markdown" = "dev.zed.Zed.desktop";
    };
  };

  # ─────────────────────────────────────────────────────────────
  # GTK Theme (for icons in notifications and apps)
  # ─────────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Alacritty
  # ─────────────────────────────────────────────────────────────
  programs.alacritty = {
    enable = true;
    settings = {
      general.import = [ "${alacrittyThemes}/themes/${alacrittyTheme}.toml" ];
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

  # ─────────────────────────────────────────────────────────────
  # Fuzzel (app launcher)
  # ─────────────────────────────────────────────────────────────
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka Nerd Font:size=12";
        prompt = "❯ ";
        icon-theme = "Adwaita";
        icons-enabled = true;
        terminal = "alacritty -e";
        layer = "overlay";
        width = 50;
        horizontal-pad = 20;
        vertical-pad = 15;
        inner-pad = 10;
        lines = 12;
      };
      colors = {
        background = "2b303bdd";
        text = "ffffffee";
        match = "7fc8ffff";
        selection = "64727dff";
        selection-text = "ffffffff";
        selection-match = "7fc8ffff";
        border = "64727dff";
      };
      border = {
        width = 2;
        radius = 12;
      };
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Waybar
  # ─────────────────────────────────────────────────────────────
  programs.waybar = {
    enable = true;
    # Style managed separately due to complexity
    # Config managed separately due to custom modules
  };

  # ─────────────────────────────────────────────────────────────
  # btop (system monitor)
  # ─────────────────────────────────────────────────────────────
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "Default";
      theme_background = true;
      truecolor = true;
      rounded_corners = true;
      graph_symbol = "braille";
      shown_boxes = "cpu mem net proc";
      update_ms = 2000;
      proc_sorting = "cpu lazy";
      proc_colors = true;
      proc_gradient = true;
      proc_mem_bytes = true;
      proc_cpu_graphs = true;
      cpu_invert_lower = true;
      show_uptime = true;
      show_cpu_watts = true;
      check_temp = true;
      show_coretemp = true;
      temp_scale = "celsius";
      show_cpu_freq = true;
      clock_format = "%X";
      mem_graphs = true;
      show_swap = true;
      swap_disk = true;
      show_disks = true;
      only_physical = true;
      use_fstab = true;
      show_io_stat = true;
      net_auto = true;
      net_sync = true;
      show_battery = true;
      show_battery_watts = true;
      log_level = "WARNING";
      gpu_mirror_graph = true;
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Notification Daemon (mako)
  # ─────────────────────────────────────────────────────────────
  services.mako = {
    enable = true;
    
    # All settings must be in 'settings' block now
    settings = {
      # Appearance
      background-color = "#1e1e2e";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 2;
      border-radius = 10;
      padding = "15";
      margin = "10";
      
      # Size
      width = 500;
      height = 200;
      
      # Output
      output = "eDP-1";  # Only show on laptop screen (privacy)
      
      # Text
      font = "sans-serif 16";  # 50% bigger than default
      markup = true;
      format = "<b>%s</b>\\n%b";  # Bold title, body on new line
      
      # Timeout
      default-timeout = 5000;  # 5 seconds
      
      # Icons
      icons = true;
      max-icon-size = 64;
      icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus";
    };
    
    # Urgency-specific colors
    extraConfig = ''
      [urgency=low]
      border-color=#89dceb
      
      [urgency=high]
      border-color=#f38ba8
    '';
  };

  # ─────────────────────────────────────────────────────────────
  # Dotfiles (files that Home Manager doesn't have modules for)
  # ─────────────────────────────────────────────────────────────
  # The Claude Code sandbox entries moved to home/common.nix — it needs only
  # Docker, so it is identical on every host.
  home.file = {
    # The Powerlevel10k config moved to home/common.nix, so forge gets it too.

    # Niri profiles (both available, switch with niri-profile command)
    ".config/niri/config-home.kdl".source = ../../dotfiles/niri/config-home.kdl;
    ".config/niri/config-office.kdl".source = ../../dotfiles/niri/config-office.kdl;

    # Niri profile switcher
    ".local/bin/niri-profile" = {
      source = ../../dotfiles/niri/switch-profile.sh;
      executable = true;
    };

    # Pragmasevka font
    ".local/share/fonts/Pragmasevka".source = ../../fonts/Pragmasevka;

    # Wallpaper
    ".config/wallpapers/microgpt.png".source = ../../dotfiles/wallpapers/microgpt.png;

    # Waybar config
    ".config/waybar/config.json".source = ../../dotfiles/waybar/config.json;
    ".config/waybar/style.css".source = ../../dotfiles/waybar/style.css;
    ".config/waybar/niri-workspaces.sh" = {
      source = ../../dotfiles/waybar/niri-workspaces.sh;
      executable = true;
    };
  };
  
  # Refresh font cache after installing Pragmasevka
  home.activation.refreshFonts = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -d "$HOME/.local/share/fonts/Pragmasevka" ]; then
      $DRY_RUN_CMD ${pkgs.fontconfig}/bin/fc-cache -f
    fi
  '';
  
  # Set default profile on activation (won't override if symlink already exists)
  home.activation.niriDefaultProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -e "$HOME/.config/niri/config.kdl" ]; then
      $DRY_RUN_CMD ln -s "$HOME/.config/niri/config-home.kdl" "$HOME/.config/niri/config.kdl"
      echo "Created default niri profile: home"
    fi
  '';
}
