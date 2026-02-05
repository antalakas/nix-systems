{ config, pkgs, ... }:

{
  # Home Manager needs this
  home.username = "andreas";
  home.homeDirectory = "/home/andreas";
  
  # This should match your NixOS version
  home.stateVersion = "24.11";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # ─────────────────────────────────────────────────────────────
  # User Packages (installed for this user only)
  # ─────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # CLI essentials
    ripgrep
    fd
    eza        # modern ls
    bat        # modern cat
    fzf        # fuzzy finder
    lazygit    # git TUI
    
    # Kubernetes utilities (global, version-agnostic)
    kubectl    # k8s CLI
    kubectx    # includes kubens
    k9s        # TUI for k8s
    stern      # multi-pod log tailing
    
    # Cloud & secrets
    aws-vault  # AWS credential management
    sops       # secrets encryption
    age        # modern encryption
    
    # Data wrangling
    yq-go      # jq for YAML
    
    # Python dev
    pixi       # modern Python/conda environment manager
    
    # Applications
    spotify
  ];

  # ─────────────────────────────────────────────────────────────
  # Direnv (auto-load dev environments)
  # ─────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;  # faster cached nix shells
  };

  # ─────────────────────────────────────────────────────────────
  # Git
  # ─────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user.name = "antalakas";
      user.email = "antalakas@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Zsh
  # ─────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    history = {
      size = 10000;
      save = 10000;
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      share = true;
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "history" "fzf" "kubectl" "aws" ];
    };
    
    initContent = ''
      # Powerlevel10k
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      
      # Aliases
      alias ls='eza --icons'
      alias ll='eza -la --icons'
      alias cat='bat'
      alias lg='lazygit'
      
      # Kubernetes aliases
      alias k='kubectl'
      alias kctx='kubectx'
      alias kns='kubens'
    '';
  };

  # ─────────────────────────────────────────────────────────────
  # XDG Config Files
  # ─────────────────────────────────────────────────────────────
  xdg.configFile = {
    # Force overwrite Alacritty config (prevent backup collisions)
    "alacritty/alacritty.toml".force = true;
    
    # aws-vault configuration
    "aws-vault/config".text = ''
      # Default session duration
      duration=8h
    '';
  };

  # ─────────────────────────────────────────────────────────────
  # Alacritty
  # ─────────────────────────────────────────────────────────────
  programs.alacritty = {
    enable = true;
    settings = {
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
      
      # Tokyo Night theme
      colors = {
        primary = {
          background = "#1a1b26";
          foreground = "#c0caf5";
        };
        cursor = {
          text = "#1a1b26";
          cursor = "#c0caf5";
        };
        selection = {
          text = "#c0caf5";
          background = "#33467c";
        };
        normal = {
          black = "#15161e";
          red = "#f7768e";
          green = "#9ece6a";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#bb9af7";
          cyan = "#7dcfff";
          white = "#a9b1d6";
        };
        bright = {
          black = "#414868";
          red = "#f7768e";
          green = "#9ece6a";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#bb9af7";
          cyan = "#7dcfff";
          white = "#c0caf5";
        };
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
  # Dotfiles (files that Home Manager doesn't have modules for)
  # ─────────────────────────────────────────────────────────────
  home.file = {
    # Powerlevel10k config (if you have one)
    # ".p10k.zsh".source = ./dotfiles/p10k.zsh;
    
    # Niri config
    ".config/niri/config.kdl".source = ./dotfiles/niri/config.kdl;
    
    # Waybar config
    ".config/waybar/config.json".source = ./dotfiles/waybar/config.json;
    ".config/waybar/style.css".source = ./dotfiles/waybar/style.css;
    ".config/waybar/niri-workspaces.sh" = {
      source = ./dotfiles/waybar/niri-workspaces.sh;
      executable = true;
    };
  };
}
