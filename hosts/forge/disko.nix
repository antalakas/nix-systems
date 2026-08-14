# Declarative partitioning for forge. Consumed by `disko` at install time and
# by the nixos module afterwards, which generates the fileSystems entries — so
# hardware-configuration.nix on this host must be generated with
# `nixos-generate-config --no-filesystems`.
#
# WARNING: running disko against these devices destroys everything on them.

{ lib, ... }:

let
  # by-id, never /dev/nvme0n1 — enumeration order is not stable across boots,
  # and getting it wrong here formats the wrong disk. These are the serials of
  # the drives actually in the machine; re-read `ls -l /dev/disk/by-id/` before
  # trusting this file again if either is ever swapped.
  mainDisk = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_4000GB_262004800250";
  scratchDisk = "/dev/disk/by-id/nvme-PC_SN810_NVMe_WDC_1024GB_230993473207";
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
                #
                # NOTE: btrfs ignores the nodatacow below. Mount options are
                # applied per filesystem, not per subvolume — the first mount
                # wins and the rest are dropped, so this subvolume comes up
                # with the `compress=zstd` from "/root" instead. It is kept
                # because it states the intent at the point of definition, and
                # would take effect if btrfs ever gains per-subvolume options.
                # What actually disables COW is the systemd.tmpfiles rule in
                # default.nix; the two have to stay in step.
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
