# Declarative partitioning for nuc. Consumed by `disko` at install time and by
# the nixos module afterwards, which generates the fileSystems entries — so
# hardware-configuration.nix on this host must be generated with
# `nixos-generate-config --no-filesystems`.
#
# WARNING: running disko against these devices destroys everything on them.
#
# Same two-disk shape as hosts/forge/disko.nix: the fast drive carries the
# system, the slower one is kept separate as bulk storage. Here that is an
# NVMe 970 PRO and a SATA 850 PRO, both 512G — a closer pair than forge's
# 4TB/1TB split, so the reason for keeping them apart is the weaker one of the
# two forge has: not "the backup target must survive the main drive" (nothing
# backs up here yet) but simply that /srv should not compete with the root
# filesystem for the same spindle.

{ lib, ... }:

let
  # by-id, never /dev/nvme0n1 or /dev/sda — enumeration order is not stable
  # across boots, and getting it wrong here formats the wrong disk.
  #
  # Both of these were read off the machine while it still ran Ubuntu. The
  # kernel also exposes the NVMe as `nvme-eui.0025385991b3924d` and as a
  # duplicate `..._S463NF0M915208E_1` alias; the model+serial form below is the
  # stable, readable one. Re-read `ls -l /dev/disk/by-id/` before trusting this
  # file again if either drive is ever swapped.
  mainDisk = "/dev/disk/by-id/nvme-Samsung_SSD_970_PRO_512GB_S463NF0M915208E";
  scratchDisk = "/dev/disk/by-id/ata-Samsung_SSD_850_PRO_512GB_S250NXAGB30165T";
in
{
  disko.devices.disk = {
    # 512G Samsung 970 PRO (NVMe) — system, home, nix store and docker. This is
    # the drive Ubuntu booted from, where it kept a 1G ESP, a 2G /boot and an
    # LVM PV whose volume group only ever allocated 100G of the 474G available.
    # None of that survives: the layout below replaces it wholesale.
    main = {
      device = mainDisk;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # 1G, matching forge. The ESP is the one partition that is painful to
          # resize later, and a full /boot fails a rebuild partway through
          # installing the new entry. 1G affords boot.loader.systemd-boot's
          # configurationLimit = 20 in ./default.nix; the two go together.
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
          root = {
            size = "100%";
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
                # Container layers are written once and read many times, and
                # copy-on-write plus compression on top of overlay2 buys
                # fragmentation rather than space.
                #
                # NOTE: btrfs ignores the nodatacow below — mount options are
                # applied per filesystem, not per subvolume, so the first mount
                # wins and this subvolume comes up with the `compress=zstd`
                # from "/root" instead. It is kept because it states the intent
                # at the point of definition. What actually disables COW is the
                # systemd.tmpfiles rule in ./default.nix; the two have to stay
                # in step. Same trade as forge.
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

    # 512G Samsung 850 PRO (SATA) — bulk storage at /srv.
    #
    # Under Ubuntu this was one full-disk ext4 partition mounted at
    # /home/andreas/ssd, and empty: 444.5G of 476.9G free, which is a fresh
    # filesystem once ext4's reserved blocks and journal are accounted for.
    # Checked before the wipe, so nothing was lost here.
    #
    # The mountpoint moves to /srv rather than staying under /home, matching
    # forge. Mounting it back at /home/andreas/ssd would work but nests it
    # inside the /home subvolume above, which is fussier than it is worth.
    scratch = {
      device = scratchDisk;
      type = "disk";
      content = {
        type = "gpt";
        partitions.srv = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes."/srv" = {
              mountpoint = "/srv";
              mountOptions = [ "compress=zstd" "noatime" ];
            };
          };
        };
      };
    };
  };
}
