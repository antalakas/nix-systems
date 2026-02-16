# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./configuration-niri.nix
    ]
    ++ (if builtins.pathExists ./wireguard-secrets.nix 
        then [ ./wireguard-secrets.nix ] 
        else [ ]);

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Mount old EndeavourOS partition (for extra storage, repos, ollama models)
  fileSystems."/mnt/endeavouros" = {
    device = "/dev/disk/by-uuid/9e4b9715-a8d3-4a1d-9ecf-47e392c12d31";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Athens";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "el_GR.UTF-8";
    LC_IDENTIFICATION = "el_GR.UTF-8";
    LC_MEASUREMENT = "el_GR.UTF-8";
    LC_MONETARY = "el_GR.UTF-8";
    LC_NAME = "el_GR.UTF-8";
    LC_NUMERIC = "el_GR.UTF-8";
    LC_PAPER = "el_GR.UTF-8";
    LC_TELEPHONE = "el_GR.UTF-8";
    LC_TIME = "el_GR.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.andreas = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "andreas";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Allow insecure packages (required for sublime4)
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"  # Required by Sublime Text 4
  ];
  
  # Enable user namespaces (required for Electron apps like Tutanota)
  security.unprivilegedUsernsClone = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    git
    jq
    alacritty
    fuzzel
    firefox
    waybar
    code-cursor
    brave
    xwayland-satellite
    psmisc
    networkmanagerapplet
    adwaita-icon-theme
    mesa-demos
    btop
    nvtopPackages.full
    ollama
    zsh-powerlevel10k
    slack
    discord
    logseq
    
    # CUDA toolkit
    cudatoolkit
    
    # DNS tools (nslookup, dig)
    dnsutils
    
    # Screenshot tools (Flameshot alternative for Wayland)
    grim          # screenshot capture
    slurp         # region selection
    satty         # annotation/editing
    wl-clipboard  # clipboard support
    
    # File manager
    doublecmd     # dual-pane file manager
  ];

  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Enable nix-ld for running dynamically linked binaries (pixi, conda, etc.)
  programs.nix-ld.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # Docker (data root on EndeavourOS partition for images/containers)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    daemon.settings = {
      data-root = "/mnt/endeavouros/var/lib/docker";
    };
  };

  # Tailscale VPN
  services.tailscale.enable = true;

  # plocate (fast file location)
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  # 1Password (for browser extension integration)
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "andreas" ];
  };

  # Enable OpenGL
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;  # 32-bit support for Steam games

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;  # Steam Remote Play
    dedicatedServer.openFirewall = true;  # Source dedicated servers
    gamescopeSession.enable = true;  # GameScope compositor for better gaming
  };

  # NVIDIA drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Enable zsh system-wide
  programs.zsh = {
    enable = true;
    histSize = 10000;
    histFile = "$HOME/.zsh_history";
    setOptions = [
      "SHARE_HISTORY"
      "HIST_IGNORE_DUPS"
      "HIST_IGNORE_SPACE"
      "HIST_EXPIRE_DUPS_FIRST"
      "HIST_FIND_NO_DUPS"
    ];
    promptInit = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
    '';
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";  # or "agnoster", "powerlevel10k", etc.
      plugins = [ "git" "sudo" "docker" "history" ];
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Display Manager - greetd with tuigreet
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

  security.polkit.enable = true;

  services.dbus.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common.default = [ "wlr" "gtk" ];
      niri.default = lib.mkForce [ "wlr" "gtk" ];
    };
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    nerd-fonts.iosevka
  ];

  # Ollama for local LLMs with NVIDIA GPU
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };
}
