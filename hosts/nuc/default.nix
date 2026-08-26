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
    ../../modules/common.nix
    ../../modules/server.nix
    ../../modules/k8s-dev.nix
  ];

  networking.hostName = "nuc";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Conservative until this box's ESP size is known: a full /boot fails the
  # rebuild partway through installing the new entry. forge's 1G ESP affords
  # 20, the laptop's 256M one affords 10.
  boot.loader.systemd-boot.configurationLimit = 10;

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

  # Nothing here sets virtualisation.docker.daemon.settings or the tmpfiles
  # NOCOW rule that forge needs: both exist because forge puts /var/lib/docker
  # on its own btrfs subvolume. Revisit if this host ends up on btrfs too —
  # see the storage-driver comment in hosts/forge/default.nix.

  # The LAN way in, for the day Tailscale is the thing that broke. Tailscale
  # SSH (modules/server.nix) authenticates against tailnet ACLs and ignores
  # this list entirely.
  users.users.andreas.openssh.authorizedKeys.keys = [
    # the laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlPc0tM6OBS5qjtF4OOieQAXa7ki0AD78YK+7i4thkc antalakas@gmail.com"
  ];

  # No secrets.nix/backup.nix pair like forge's. sops-nix cannot encrypt for a
  # host until it has an SSH host key, which only exists after the first
  # install; add a nuc entry to .sops.yaml then, and gate the import on
  # `builtins.pathExists ../../secrets/nuc.yaml` the way hosts/forge does.

  # The release this host was first installed from. Set once, at install, and
  # left alone: it pins compatibility defaults for stateful services, so moving
  # it later silently changes them under existing data. 26.11 is what forge was
  # installed from — confirm it against the installer before the first switch.
  system.stateVersion = "26.11";
}
