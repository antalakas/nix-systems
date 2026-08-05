# forge — headless development box (Minisforum MS-02 Ultra, Core Ultra 9 285HX).
#
# No display stack, no audio, no printing: reached over SSH from the laptop,
# normally across the tailnet. Everything that needs a screen belongs on the
# laptop; this machine runs Docker, kind clusters and the Claude Code sandbox.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/common.nix
    ../../modules/server.nix
    ../../modules/k8s-dev.nix
  ]
  # sops-nix cannot encrypt for this host until it has an SSH host key, which
  # only exists after the first install. Until secrets/forge.yaml is committed,
  # Tailscale is brought up by hand once and nothing here references a secret.
  ++ lib.optional (builtins.pathExists ../../secrets/forge.yaml) ./secrets.nix;

  networking.hostName = "forge";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # /boot is 1G here, so this is roomier than the laptop's cap — but bounded,
  # because a full ESP fails the rebuild halfway through installing an entry.
  boot.loader.systemd-boot.configurationLimit = 20;

  # Arrow Lake-HX is recent enough that the newest kernel is the safe choice.
  # Revisit once the default nixpkgs kernel is comfortably past it.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Non-negotiable on this board: the dual 25GbE SFP28 ports are Intel E810,
  # whose `ice` driver refuses to initialise without its DDP firmware package.
  # The i226 2.5GbE and BE200 Wi-Fi want firmware blobs too.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # 24 cores in a small chassis; let thermald manage the throttling policy
  # rather than discovering the hardware's own limits under a long build.
  services.thermald.enable = true;

  # NetworkManager rather than systemd-networkd, to match the laptop and to
  # keep `nmcli` available for a WireGuard profile later. DHCP on whichever
  # port is patched, so no interface is named here.
  networking.networkmanager.enable = true;

  # No swap partition — zram absorbs spikes without writing to the SSD. Revisit
  # if you start running clusters big enough to actually need to page out.
  zramSwap.enable = true;

  # /var/lib/docker is its own btrfs subvolume (see disko.nix). overlay2 is
  # named explicitly because docker would otherwise pick its btrfs driver on a
  # btrfs filesystem, which is the less-travelled path.
  virtualisation.docker.daemon.settings = {
    storage-driver = "overlay2";
  };

  users.users.andreas.openssh.authorizedKeys.keys = [
    # TODO: paste the laptop's ~/.ssh/id_ed25519.pub here to enable LAN SSH.
    #
    # Not needed for tailnet access: Tailscale SSH (modules/server.nix) checks
    # tailnet ACLs, not this list. Leaving it empty means the only paths in are
    # the tailnet and the physical console — which is a real corner to be
    # painted into if Tailscale is ever the thing that broke.
  ];

  # The release this host was first installed from. Set once, at install, and
  # left alone: it pins compatibility defaults for stateful services, so moving
  # it later silently changes them under existing data.
  system.stateVersion = "26.11";
}
