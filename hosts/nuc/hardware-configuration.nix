# PLACEHOLDER — not a real hardware scan.
#
# This file has to come from the machine itself: it carries the filesystem
# UUIDs, the initrd kernel modules needed to reach the root device, and the
# CPU microcode default. None of it can be written off-host, and guessing it
# produces a system that does not boot.
#
# It throws rather than being absent so that a rebuild of #nuc fails here with
# an explanation, instead of failing somewhere further in with a missing
# fileSystems."/" error. Note that `nix flake check` evaluates every output, so
# it will trip on this too until the file is replaced.

throw ''
  hosts/nuc/hardware-configuration.nix is still the placeholder.

  On the nuc — from the installer, or from the running system:

      sudo nixos-generate-config --no-filesystems --show-hardware-config \
        > hosts/nuc/hardware-configuration.nix

  --no-filesystems because ./disko.nix already declares every filesystem, and
  a second set of definitions collides with it.

  Do this BEFORE running disko, which is the opposite of the order in
  docs/forge-install.md (§3 partitions, §4 scans). That order cannot work on a
  host whose scan is still this file: `disko --mode ... --flake .#nuc` has to
  evaluate nixosConfigurations.nuc to reach disko.devices, evaluating it
  imports this file, and importing it lands you here. Writing the scan first
  breaks the cycle, and --show-hardware-config needs nothing mounted to run.

  Replace this file with that output, then check it before switching:

    - fileSystems entries point at /dev/disk/by-uuid/..., not /dev/sdX
    - boot.initrd.availableKernelModules covers the root device's controller
    - swapDevices matches reality (this host sets zramSwap instead, so an
      empty list is expected unless you made a swap partition)

  Everything else for this host is already written: hosts/nuc/default.nix,
  hosts/nuc/home.nix, and the nixosConfigurations.nuc output in flake.nix.
''
