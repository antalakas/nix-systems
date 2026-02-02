# Niri configuration using niri-flake
# The niri-flake module doesn't provide programs.niri.settings
# So we use it just for enabling niri and manage the config file manually
# Your existing ~/.config/niri/config.kdl will be used

{ config, pkgs, inputs, ... }:

{
  # Enable niri using the flake module
  # This provides the niri package and systemd integration
  # The config file at ~/.config/niri/config.kdl is managed manually
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
