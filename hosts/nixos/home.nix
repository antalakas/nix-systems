{ config, pkgs, lib, ... }:

{
  # The CLI toolchain, git, zsh, tmux, direnv, neovim and the Claude Code
  # sandbox come from home/common.nix. What is left here is the desktop.
  # home/alacritty.nix carries the terminal config every graphical host shares;
  # only the theme below is host-specific.
  imports = [ ../../home/common.nix ../../home/alacritty.nix ];

  # This should match your NixOS version
  home.stateVersion = "24.11";

  # Where claude-sandbox resolves refs.conf's reference mounts from. This host
  # keeps its repos on the old EndeavourOS partition rather than under $HOME,
  # which is the only reason refs.conf needs a root at all — forge takes the
  # default ($HOME/workspace) and sets nothing. See dotfiles/claude-code/refs.conf.
  home.sessionVariables.CLAUDE_REFS_ROOT = "/mnt/endeavouros/home/andreas/workspace";

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
    nautilus          # GUI file manager; also the inode/directory handler the
                      # portal needs for "open containing folder" (see mimeApps)
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

    # Undo a remote shell's tint. home/ssh-tint.nix repaints this terminal over
    # OSC 11 for the length of an ssh session and restores it from zshexit, but
    # a dropped connection never runs that hook and would strand the window
    # tinted until you reset it by hand. Host-agnostic on purpose: every host
    # that enables the tint is covered here without naming any of them.
    #
    # A precmd rather than a one-shot at startup, because the shell that ran
    # `ssh <host>` is still alive underneath the connection: when it dies you are
    # returned to that shell, which never re-sources .zshrc. Its next prompt is
    # the first local code to run, so that is where the reset belongs. OSC 111
    # is a no-op when nothing has been tinted, and one write per prompt does not
    # register.
    #
    # Skipped inside tmux, where it would be pointless rather than wrong: a
    # multiplexer that will not forward the tint out will not forward the reset
    # either, so neither ever reaches alacritty.
    if [[ -o interactive && -z $SSH_CONNECTION && -z $TMUX ]]; then
      autoload -Uz add-zsh-hook
      _reset_term_bg() { printf '\033]111\a'; }
      add-zsh-hook precmd _reset_term_bg
    fi
  '';

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

      # "Open containing folder" in flatpak apps (Slack) goes through the
      # portal's OpenURI.OpenDirectory, which dispatches on inode/directory.
      # With no handler registered the call silently no-ops rather than
      # erroring, which reads as a broken button.
      "inode/directory" = "org.gnome.Nautilus.desktop";
    };
  };

  # ─────────────────────────────────────────────────────────────
  # XDG user directories
  # ─────────────────────────────────────────────────────────────
  # Required for the Slack flatpak's --filesystem=xdg-download to work at all.
  # Flatpak resolves xdg-download via g_get_user_special_dir(), which reads
  # ~/.config/user-dirs.dirs; with no such file GLib returns NULL (only
  # DESKTOP has a built-in fallback), so flatpak skips the mount entirely.
  # Slack then falls back to $HOME/Downloads inside the sandbox — and since
  # it has no --filesystem=home, that path is flatpak's tmpfs, so every
  # download silently vanished on restart.
  # user-dirs.dirs is what flatpak reads, so the XDG_*_DIR session variables
  # buy nothing here. home-manager's new default drops them (they go stale
  # whenever the file changes); pinned explicitly because home.stateVersion is
  # below 26.05, which would otherwise keep the legacy `true` and warn.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false;
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
  # Alacritty — the rest of the config is in home/alacritty.nix
  # ─────────────────────────────────────────────────────────────
  my.alacritty.theme = "rose_pine";

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
