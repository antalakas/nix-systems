# Declarative partitioning for forge. Consumed by `disko` at install time and
# by the nixos module afterwards, which generates the fileSystems entries — so
# hardware-configuration.nix on this host must be generated with
# `nixos-generate-config --no-filesystems`.
#
# WARNING: running disko against these devices destroys everything on them.

{ lib, ... }:

let
  # TODO: replace both with stable paths from `ls -l /dev/disk/by-id/`.
  # by-id, never /dev/nvme0n1 — enumeration order is not stable across boots,
  # and getting it wrong here formats the wrong disk.
  mainDisk = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_4000GB_REPLACE_ME";
  scratchDisk = "/dev/disk/by-id/nvme-REPLACE_ME_1TB";
in
{
  disko.devices.disk = {
    # 4TB WD_BLACK SN850X — system, home, nix store and docker.
    main = {
      device = mainDisk;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
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
                # fragmentation rather than space. nodatacow also switches off
                # checksums for this subvolume, which is the trade: docker
                # state is reproducible, /home is not.
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

    # 1TB NVMe salvaged from the Latitude — backup target and bulk scratch.
    # Deliberately not part of the main filesystem: it is the older, slower
    # drive, and keeping it separate means a restic repo here survives anything
    # done to the 4TB.
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
