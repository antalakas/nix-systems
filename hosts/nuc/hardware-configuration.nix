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

      nixos-generate-config --show-hardware-config

  Replace this file with that output, then check it before switching:

    - fileSystems entries point at /dev/disk/by-uuid/..., not /dev/sdX
    - boot.initrd.availableKernelModules covers the root device's controller
    - swapDevices matches reality (this host sets zramSwap instead, so an
      empty list is expected unless you made a swap partition)

  Everything else for this host is already written: hosts/nuc/default.nix,
  hosts/nuc/home.nix, and the nixosConfigurations.nuc output in flake.nix.
''
