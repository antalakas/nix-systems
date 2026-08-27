# nuc — headless always-on box. Same shape as forge: no display stack, no
# audio, no printing, reached over SSH and normally across the tailnet.
#
# What forge and this host do not share is hardware, so forge's hardware
# tuning — its kernel pin, its E810 DDP firmware, its Wake-on-LAN interface —
# is deliberately absent here rather than copied across. Add back only what
# this machine turns out to need.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/common.nix
    ../../modules/server.nix
    ../../modules/k8s-dev.nix
  ]
  # Same bootstrap order as forge: sops-nix cannot encrypt for this host until
  # it has an SSH host key, which only exists after the first install. Until
  # secrets/nuc.yaml is committed, Tailscale is brought up by hand once and
  # nothing here references a secret. No backup.nix counterpart rides along:
  # this host has a second disk at /srv like forge does, but no restic units
  # are set up on it yet.
  ++ lib.optionals (builtins.pathExists ../../secrets/nuc.yaml) [
    ./secrets.nix
  ];

  networking.hostName = "nuc";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # ./disko.nix fixes the ESP at 1G, so this can match forge rather than the
  # laptop's 256M cap. Still bounded: a full /boot fails the rebuild partway
  # through installing the new entry.
  boot.loader.systemd-boot.configurationLimit = 20;

  # No boot.kernelPackages pin on purpose. forge runs linuxPackages_latest
  # only because Arrow Lake-HX is newer than the default kernel knows about;
  # unless this machine has the same problem, the default is the safe choice.

  # Microcode plus the Wi-Fi/NIC firmware blobs an Intel NUC wants. If this is
  # one of the AMD-based models, swap the second line for
  # hardware.cpu.amd.updateMicrocode.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # NetworkManager to match the other two hosts, and to keep nmcli around.
  networking.networkmanager.enable = true;

  # No Wake-on-LAN yet: it is the one setting that has to name an interface and
  # its MAC, and neither is knowable off the machine. See
  # networking.interfaces.eno2.wakeOnLan in hosts/forge/default.nix for the
  # shape, and docs/forge-install.md §11 for verifying it with ethtool rather
  # than trusting the config.

  # zram rather than a swap partition, as on forge — a NUC is usually the
  # RAM-limited box in the house, and this absorbs spikes without writing to
  # the SSD.
  zramSwap.enable = true;

  # This host did end up on btrfs with /var/lib/docker on its own subvolume
  # (./disko.nix), which is the condition the two settings below exist for.
  # They are forge's, verbatim; the reasoning is spelled out at length in
  # hosts/forge/default.nix.
  #
  # overlay2 is named explicitly because docker would otherwise pick its btrfs
  # driver on a btrfs filesystem, which is the less-travelled path.
  virtualisation.docker.daemon.settings = {
    storage-driver = "overlay2";
  };

  # This, not the `nodatacow` in disko.nix, is what actually disables COW for
  # container layers: btrfs applies most mount options per filesystem rather
  # than per subvolume, so /var/lib/docker inherits the `compress=zstd` that /
  # was mounted with. tmpfiles runs well before docker.service, so on a fresh
  # install the subvolume is still empty when this lands and everything docker
  # writes inherits NOCOW. It only affects new files, so it cannot repair a
  # subvolume that already has data.
  systemd.tmpfiles.rules = [ "h /var/lib/docker - - - - +C" ];

  # The LAN way in, for the day Tailscale is the thing that broke. Tailscale
  # SSH (modules/server.nix) authenticates against tailnet ACLs and ignores
  # this list entirely.
  users.users.andreas.openssh.authorizedKeys.keys = [
    # the laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlPc0tM6OBS5qjtF4OOieQAXa7ki0AD78YK+7i4thkc antalakas@gmail.com"
  ];

  # ./secrets.nix is written and imported conditionally above. What is still
  # missing is the encrypted file it points at: after the first install, derive
  # this host's age key with `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`,
  # add it to .sops.yaml, and create secrets/nuc.yaml. Until then the import
  # does not fire and nothing here needs a secret.

  # The release this host was first installed from. Set once, at install, and
  # left alone: it pins compatibility defaults for stateful services, so moving
  # it later silently changes them under existing data. 26.11 is what forge was
  # installed from — confirm it against the installer before the first switch.
  system.stateVersion = "26.11";
}
