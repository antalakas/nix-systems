# Niri Wayland compositor configuration
# Uses the built-in nixpkgs programs.niri module
# Config file at ~/.config/niri/config.kdl is managed via Home Manager

{ config, pkgs, ... }:

{
  # Enable niri (nixpkgs built-in module)
  programs.niri.enable = true;
  
  # Waybar is already configured via config files at ~/.config/waybar/
  # The waybar package should be installed via environment.systemPackages
  # No NixOS module configuration needed - your existing config files work
  
  # Environment variables for Wayland
  environment.variables = {
    MOZ_ENABLE_WAYLAND = "1";
  };
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_CURRENT_DESKTOP = "niri";
  };
  
}
