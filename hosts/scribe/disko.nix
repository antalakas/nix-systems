# Declarative partitioning for scribe. Consumed by `disko` at install time and
# by the nixos module afterwards, which generates the fileSystems entries — so
# hardware-configuration.nix on this host must be generated with
# `nixos-generate-config --no-filesystems`.
#
# WARNING: running disko against this device destroys everything on it.
#
# Two things differ from hosts/nuc/disko.nix, and both follow from what this
# machine is:
#
#   1. One disk. The XPS 9310 has a single M.2 2280 slot, so there is no
#      second drive to keep /srv on and no choice to make about it.
#   2. LUKS. This is the only host in the flake that leaves the house, which
#      makes it the only one where "someone else is holding the disk" is a
#      realistic state. What is on it is not really the point — it is the SSH
#      host key, the age key derived from it, and the tailnet node key, which
#      together are a working identity on the tailnet rather than a laptop.
#      Encryption cannot be added later without a reinstall, which is why it is
#      here on day one.

{ lib, ... }:

let
  # by-id, never /dev/nvme0n1 — enumeration order is not stable across boots,
  # and getting it wrong here formats the wrong disk.
  #
  # Read off this machine during its install rather than from an older OS, as
  # nuc's were. To read it again — a disk swap, or a second machine — boot the
  # installer and run:
  #
  #   ls -l /dev/disk/by-id/ | grep -v part
  #
  # taking the `nvme-<model>_<serial>` form: readable, and stable across the
  # `nvme-eui.*` and `..._1` duplicate aliases the kernel also exposes.
  #
  # If nothing NVMe appears at all, the disk is not missing: the 9310 ships
  # with BIOS `SATA Operation` set to RAID/Intel RST, under which the Linux
  # NVMe driver cannot see the drive. Switch it to AHCI. See
  # docs/scribe-install.md §1.
  mainDisk = "/dev/disk/by-id/nvme-PC_SN730_NVMe_WDC_1024GB_2041C7801763";
in
{
  disko.devices.disk.main = {
    device = mainDisk;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # 1G, matching forge and nuc. The ESP is the one partition that is
        # painful to resize later, and a full /boot fails a rebuild partway
        # through installing the new entry. 1G affords
        # boot.loader.systemd-boot.configurationLimit = 20 in ./default.nix;
        # the two go together.
        #
        # Unencrypted, necessarily: the firmware has to read the bootloader,
        # the kernel and the initrd before anything can ask for a passphrase.
        # Nothing secret is in there — the initrd holds no key file, because
        # the volume below is opened by typing the passphrase rather than from
        # a keyfile baked into the image.
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };

        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";

            # No `passwordFile`. disko prompts on the tty instead — twice
            # during the install, once to format and once to open — and that is
            # the point: a path named here would have to exist on the installer
            # at exactly the moment it runs, and anything committed to this
            # repo is not a secret. See docs/scribe-install.md §4 for the
            # non-interactive alternative if you ever need to script this.
            settings = {
              # Pass TRIM through to the SSD. Without it the controller never
              # learns which blocks are free, and a laptop SSD that is never
              # trimmed slows down and wears faster. The cost is a known and
              # accepted leak: an attacker holding the powered-off disk can see
              # how much of it is in use and roughly where, but not what any of
              # it is. Standard trade for a laptop; drop the line if this ever
              # holds something where the shape of the data is itself
              # sensitive.
              allowDiscards = true;
            };

            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              # Names carry a leading slash to match disko's own examples; it
              # derives the `subvol=` mount option from them.
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                # Declared even though this host is not meant to run containers
                # — Claude Code runs on forge. It costs nothing empty, and the
                # NOCOW attribute that makes it worth having can only be set on
                # an empty directory, so the alternative to declaring it now is
                # moving data later.
                #
                # NOTE: btrfs ignores the nodatacow below — mount options are
                # applied per filesystem, not per subvolume, so the first mount
                # wins and this subvolume comes up with the `compress=zstd`
                # from "/root" instead. It is kept because it states the intent
                # at the point of definition. What actually disables COW is the
                # systemd.tmpfiles rule in ./default.nix; the two have to stay
                # in step. Same trade as forge and nuc.
                "/docker" = {
                  mountpoint = "/var/lib/docker";
                  mountOptions = [ "noatime" "nodatacow" ];
                };
                "/snapshots" = {
                  mountpoint = "/.snapshots";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
