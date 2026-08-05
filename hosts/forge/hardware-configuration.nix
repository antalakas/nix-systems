# PLACEHOLDER — replace with the real thing during install:
#
#   nixos-generate-config --no-filesystems --root /mnt
#   cp /mnt/etc/nixos/hardware-configuration.nix hosts/forge/
#
# --no-filesystems matters: disko.nix owns every fileSystems entry, and a
# generated copy of them would collide with it.
#
# The values below are a plausible guess for this board so the flake evaluates
# before the machine exists. They are not a substitute for the scan.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # fileSystems and swapDevices come from disko.nix.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
