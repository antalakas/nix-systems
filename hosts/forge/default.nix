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
  # port is patched, so no interface is named for addressing — the one below is
  # named only because Wake-on-LAN cannot be expressed without it.
  networking.networkmanager.enable = true;

  # eno2 is the patched port — MAC 38:05:25:37:b8:40, the address the Pi sends
  # the magic packet to. It is recorded here because forge cannot tell you its
  # own MAC while powered down, which is exactly when you need it. eno1
  # (38:05:25:37:b8:41) is the unused twin.
  #
  # This is the one setting that has to know the interface name (it becomes a
  # systemd .link file with WakeOnLan=magic, applied by udev, so NetworkManager
  # not being networkd does not matter). With it plus the BIOS wake settings,
  # the always-on Raspberry Pi on this LAN can power the box back up — the only
  # remote-power story available without IPMI. See docs/forge-install.md §11,
  # which also covers verifying it with ethtool rather than trusting the config.
  networking.interfaces.eno2.wakeOnLan.enable = true;

  # No swap partition — zram absorbs spikes without writing to the SSD. Revisit
  # if you start running clusters big enough to actually need to page out.
  zramSwap.enable = true;

  # /var/lib/docker is its own btrfs subvolume (see disko.nix). overlay2 is
  # named explicitly because docker would otherwise pick its btrfs driver on a
  # btrfs filesystem, which is the less-travelled path.
  virtualisation.docker.daemon.settings = {
    storage-driver = "overlay2";
  };

  # This, not the `nodatacow` in disko.nix, is what actually disables COW for
  # container layers: btrfs applies most mount options per filesystem rather
  # than per subvolume, so the options on every subvolume after the first are
  # silently dropped and /var/lib/docker inherits the `compress=zstd` that /
  # was mounted with. Verified on the install media — findmnt showed
  # compress=zstd:3 and no nodatacow on the docker subvolume.
  #
  # The inode attribute is honoured per directory, and tmpfiles runs well
  # before docker.service, so on a fresh install the subvolume is still empty
  # when this lands and everything docker writes inherits NOCOW. It only
  # affects new files, so it cannot repair a subvolume that already has data —
  # on an existing host, move the directory aside and let docker repopulate it.
  systemd.tmpfiles.rules = [ "h /var/lib/docker - - - - +C" ];

  # Not needed for tailnet access: Tailscale SSH (modules/server.nix) checks
  # tailnet ACLs, not this list. This is the LAN path that stays open on the day
  # Tailscale is the thing that broke — otherwise the only ways in would be the
  # tailnet and the physical console.
  users.users.andreas.openssh.authorizedKeys.keys = [
    # the laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlPc0tM6OBS5qjtF4OOieQAXa7ki0AD78YK+7i4thkc antalakas@gmail.com"
  ];

  # The release this host was first installed from. Set once, at install, and
  # left alone: it pins compatibility defaults for stateful services, so moving
  # it later silently changes them under existing data.
  system.stateVersion = "26.11";
}
