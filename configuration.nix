# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:

let
  # Older nixpkgs whose builds we already have locally (or that the binary
  # cache has), used to sidestep expensive/broken local builds on unstable.
  pinnedPkgs = import inputs.nixpkgs-ollama {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./configuration-niri.nix
      /mnt/endeavouros/home/andreas/workspace/andreas/tessera/nix/langfuse.nix
    ]
    ++ (if builtins.pathExists ./wireguard-secrets.nix 
        then [ ./wireguard-secrets.nix ] 
        else [ ]);

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # /boot is a 256M ESP; without a cap a few kernel bumps fill it and the
  # rebuild fails partway through installing the new entry.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Mount old EndeavourOS partition (for extra storage, repos, ollama models)
  fileSystems."/mnt/endeavouros" = {
    device = "/dev/disk/by-uuid/9e4b9715-a8d3-4a1d-9ecf-47e392c12d31";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  networking.hostName = "nixos"; # Define your hostname.
  networking.extraHosts = ''
    172.21.255.200 app.tiledb.example.com documentation.tiledb.example.com api.tiledb.example.com jupyterhub.tiledb.example.com oauth2.tiledb.example.com
    172.20.255.200 tile-ai.local
  '';
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

  nixpkgs.overlays = [
    (final: prev: {
      oda-file-converter = final.callPackage ./pkgs/oda-file-converter/package.nix { };
      # TEMP workaround for nixpkgs#545286: since CMake 4.3.4 the CUDA backend
      # configure step needs nvcc's root in CUDAToolkit_ROOT. Mirrors the fix
      # in nixpkgs#545542 — drop this once that PR reaches nixos-unstable.
      ollama-cuda = prev.ollama-cuda.overrideAttrs (old: {
        preConfigure = (old.preConfigure or "") + ''
          if nvccExe="$(type -P nvcc)"; then
            export CUDAToolkit_ROOT="''${CUDAToolkit_ROOT:+''${CUDAToolkit_ROOT};}''${nvccExe%/bin/nvcc}"
          fi
        '';
      });
    })
  ];
  
  # Allow insecure packages (required for sublime4)
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"         # Required by Sublime Text 4
  ];

  # Upstream marks sublimetext4 broken solely because its plug-in host needs
  # the insecure OpenSSL permitted above, so the guard is redundant here.
  nixpkgs.config.problems.handlers.sublimetext4.broken = "warn";
  
  # Enable user namespaces (required for Flatpak's bubblewrap sandbox and
  # nix-store Electron apps like 1Password)
  security.unprivilegedUsernsClone = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # neovim is provided by nixvim via home-manager (see neovim.nix)
    wget
    curl
    git
    jq
    alacritty
    fuzzel
    firefox
    waybar
    brave
    xwayland-satellite
    psmisc
    networkmanagerapplet
    adwaita-icon-theme
    mesa-demos
    btop
    nvtopPackages.full
    zsh-powerlevel10k

    # CUDA toolkit
    cudatoolkit
    
    # DNS/network tools
    dnsutils   # nslookup, dig
    nmap       # network scanner
    usbutils   # lsusb, usb-devices
    
    # Build tools
    gnumake
    gcc
    
    # Screenshot tools (Flameshot alternative for Wayland)
    grim          # screenshot capture
    slurp         # region selection
    satty         # annotation/editing
    wl-clipboard  # clipboard support
    
    # Brightness control
    brightnessctl

    # Audio processing (used by Claude Code voice mode)
    sox
    
    # YubiKey
    yubioath-flutter   # Yubico Authenticator (GUI)
    yubikey-manager    # ykman CLI
    
    # File manager
    doublecmd     # dual-pane file manager

    # Tunneling
    ngrok         # secure tunnels to localhost
  ];

  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  nix.settings.pure-eval = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Hardlink identical store paths; the root filesystem runs close to full.
  nix.optimise.automatic = true;

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
  networking.firewall.checkReversePath = false;

  # Reach the ollama API (services.ollama, host = "0.0.0.0") from other tailnet
  # nodes. Scoped to tailscale0 on purpose: the API is unauthenticated, so it
  # must not be exposed on the LAN or any other interface.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 11434 ];

  # Printing (Xerox B210 at 192.168.10.46)
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint pkgs.gutenprintBin ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
  hardware.printers.ensurePrinters = [
    {
      name = "XeroxB210";
      description = "Xerox B210";
      deviceUri = "ipp://192.168.10.46/ipp/print";
      model = "everywhere";
      ppdOptions.PageSize = "A4";
    }
  ];
  hardware.printers.ensureDefaultPrinter = "XeroxB210";

  # Don't fail nixos-rebuild when the printer happens to be offline.
  systemd.services.ensure-printers.serviceConfig.SuccessExitStatus = [ "0" "1" ];

  # YubiKey smartcard support
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

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
  # 3Dconnexion SpaceMouse / SpaceNavigator (open-source spacenavd; works with many older USB models)
  hardware.spacenavd.enable = true;

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

  # Lid-close behaviour.
  # We take full control via acpid instead of logind, because logind's
  # "docked" rule (triggered by >1 connected display, e.g. the 25" daisy-chained
  # off the 32" over MST) overrides the power-state rule and would keep the
  # machine awake even on battery.
  #
  # Desired rule:
  #   - on external power AND >=1 external monitor connected  -> stay on (clamshell)
  #   - anything else (notably: on battery)                   -> suspend
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  services.acpid = {
    enable = true;
    lidEventCommands = ''
      # $1 is the full event line, e.g. "button/lid LID close 00000001"
      set -- $1
      action="$3"

      # Helper: toggle the internal panel in the running niri session.
      # acpid runs as root outside the user session, so we locate niri's IPC
      # socket and run `niri msg` as the desktop user.
      niri_output() {
        runtime="/run/user/1000"
        sock=""
        for s in "$runtime"/niri.wayland-*.sock; do
          [ -S "$s" ] && sock="$s"
        done
        [ -n "$sock" ] || return 0
        ${pkgs.util-linux}/bin/runuser -u andreas -- \
          env NIRI_SOCKET="$sock" ${config.programs.niri.package}/bin/niri msg output eDP-1 "$1" || true
      }

      # Lid opened: make sure the internal panel is back on.
      if [ "$action" = "open" ]; then
        niri_output on
        exit 0
      fi

      [ "$action" = "close" ] || exit 0

      on_ac=0
      for f in /sys/class/power_supply/*/online; do
        [ -r "$f" ] || continue
        read -r v < "$f" || continue
        [ "$v" = "1" ] && on_ac=1
      done

      ext_mon=0
      for s in /sys/class/drm/*/status; do
        conn=''${s#/sys/class/drm/}
        conn=''${conn%/status}
        # Skip the internal laptop panel(s).
        case "$conn" in
          *eDP*|*LVDS*|*DSI*) continue ;;
        esac
        read -r st < "$s" 2>/dev/null || continue
        [ "$st" = "connected" ] && ext_mon=1
      done

      # Clamshell mode: keep running (and blank the hidden internal panel) only
      # when on external power with an external display present.
      if [ "$on_ac" = "1" ] && [ "$ext_mon" = "1" ]; then
        niri_output off
        exit 0
      fi

      ${pkgs.systemd}/bin/systemctl suspend
    '';
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

  # Flatpak for apps kept outside the nix store — Electron apps whose nixpkgs
  # packages pin EOL Electrons or lag upstream. Managed declaratively via
  # nix-flatpak (installed on activation; flathub is its default remote).
  services.flatpak = {
    enable = true;
    packages = [
      "com.logseq.Logseq"
      "com.slack.Slack"
      "com.spotify.Client"
      "com.tutanota.Tutanota"
    ];
  };

  # Portals. Deliberately no `config` block here: programs.niri already sets
  # xdg.portal.config.niri = [ "gnome" "gtk" ] plus extraPortals =
  # [ xdg-desktop-portal-gnome ], and defining config.niri replaces that
  # wholesale. ScreenCast must land on the gnome backend — niri implements the
  # org.gnome.Mutter.ScreenCast D-Bus API that backend drives, and does not
  # work with xdg-desktop-portal-wlr, so routing it to wlr silently kills
  # browser screen sharing.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    nerd-fonts.iosevka
  ];

  # Ollama for local LLMs with NVIDIA GPU. Taken from the pinned
  # nixpkgs-ollama input so it reuses the already-built store path instead of
  # recompiling the (uncached, unfree) CUDA build on every nixpkgs bump.
  services.ollama = {
    enable = true;
    package = pinnedPkgs.ollama-cuda;
    # Listen on all interfaces so other machines on the LAN (and containers)
    # can reach the API, not just localhost.
    host = "0.0.0.0";
    # Static user instead of DynamicUser so the models can live outside
    # /var/lib — the root filesystem is too small to hold them.
    user = "ollama";
    group = "ollama";
    modelsDir = "/mnt/endeavouros/ollama/models";
  };
}
