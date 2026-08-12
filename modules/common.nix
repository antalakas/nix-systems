# Configuration shared by every host in this flake.
#
# Anything in here must make sense on both a laptop with a desktop session and
# a headless box reached only over SSH. Host-specific hardware, storage paths
# and services belong in hosts/<name>/, not here.

{ config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Hardlink identical store paths.
  nix.optimise.automatic = true;

  # Run dynamically linked binaries that expect a normal FHS loader (pixi,
  # conda, and — on the headless host — Zed's remote server and the node it
  # downloads for language servers).
  programs.nix-ld.enable = true;

  time.timeZone = "Europe/Athens";
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

  users.users.andreas = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "andreas";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

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
    # The wizard is switched off deliberately. p10k runs it on every
    # interactive shell until ~/.p10k.zsh exists, and its final step wants to
    # append a source line to ~/.zshrc — which home-manager owns as a read-only
    # store symlink, so the option is greyed out and the wizard can never
    # complete. On a machine that has never had a p10k config the result is an
    # unusable shell: the wizard restarts on every login, including over SSH.
    #
    # Set here rather than in home/common.nix because /etc/zshrc is sourced
    # first and covers root's shell too. The default prompt is what you get;
    # run `p10k configure` by hand to produce ~/.p10k.zsh, which
    # home/common.nix sources when present.
    promptInit = ''
      POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
    '';
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "sudo" "docker" "history" ];
    };
  };

  # Docker itself is host-agnostic; where its data lives is not, so `data-root`
  # (or the filesystem mounted at /var/lib/docker) is set per host.
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  services.tailscale.enable = true;
  # Deliberately no `networking.firewall.checkReversePath` here. Tailscale's
  # NAT traversal does trip the kernel's strict reverse-path check, but the
  # nixpkgs module already relaxes it to "loose" itself — unconditionally, not
  # via mkDefault — whenever `useRoutingFeatures` is "client" or "both", as
  # modules/server.nix sets. Setting it here too collides with that rather than
  # overriding it. Hosts that need it off entirely (a full-tunnel WireGuard
  # profile, say) and do not enable routing features can set it themselves.

  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    jq
    btop
    psmisc

    # DNS/network tools
    dnsutils # nslookup, dig
    nmap

    # Build tools
    gnumake
    gcc

    zsh-powerlevel10k
  ];
}
