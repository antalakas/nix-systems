# NixOS Setup Notes

This documents the complete setup process for this NixOS system.

## System Overview

- **Compositor**: niri (Wayland scrolling tiling WM)
- **Bar**: Waybar with custom niri workspaces module
- **Terminal**: Alacritty with Tokyo Night theme
- **Shell**: Zsh + Oh-My-Zsh + Powerlevel10k
- **Launcher**: Fuzzel
- **Config Management**: NixOS + Home Manager

## Hardware

- Intel Meteor Lake-P (Intel Arc Graphics) - integrated
- NVIDIA RTX 2000 Ada Generation - discrete (hybrid/PRIME offload)
- Triple monitors:
  - **eDP-1**: Laptop display (bottom, primary reference point)
  - **DP-5**: 32" Dell U3225QE (centered above laptop)
  - **DP-4**: 27" Dell P2725QE (right side, rotated 90° CW)

## Key Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Flake entry point, Home Manager integration |
| `configuration.nix` | Main system config |
| `configuration-niri.nix` | Niri/Wayland specific settings |
| `hardware-configuration.nix` | Hardware-specific (auto-generated) |
| `home.nix` | Home Manager user config (dotfiles, user packages) |
| `dotfiles/` | Actual dotfile contents managed by Home Manager |

### Flake Structure
```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
      specialArgs = { inherit inputs; };
    };
  };
}
```

### User Configuration Files

**`~/.config/niri/config.kdl`** - Niri configuration:
- Multi-monitor layout with positions, scales, and rotation
- Environment export for systemd/dbus portal services
- Waybar autostart with delay

**`~/.config/waybar/config.json`** - Waybar configuration:
- Modules: niri-workspaces, clock, pulseaudio, network, cpu, memory, battery, tray
- Uses custom `niri-workspaces.sh` script

**`~/.config/waybar/niri-workspaces.sh`** - Workspace indicator:
```bash
#!/usr/bin/env bash
active=$(niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.is_focused == true) | .idx' 2>/dev/null)
if [ -n "$active" ]; then echo "󰧨 $active"; else echo "󰧨"; fi
```

## Important Commands

```bash
# Rebuild system
sudo nixos-rebuild switch

# Update flake inputs
sudo nix flake update

# Run GPU-intensive apps on NVIDIA
nvidia-offload <app>

# Check GPU status
nvidia-smi
nvtop

# Restart waybar after config changes
pkill waybar
waybar --config ~/.config/waybar/config.json --style ~/.config/waybar/style.css &
```

## Fixes Applied

### XDG Portal (for screen sharing, file dialogs)
The niri module had wrong portal defaults. Fixed with:
```nix
xdg.portal = {
  enable = true;
  wlr.enable = true;
  extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  config.common.default = [ "wlr" "gtk" ];
};
xdg.portal.config.niri.default = lib.mkForce [ "wlr" "gtk" ];
```

### Environment Variables for Portals
Niri config exports env to systemd at startup:
```kdl
spawn-sh-at-startup "export XDG_CURRENT_DESKTOP=niri && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
```

### Waybar Autostart
```kdl
spawn-sh-at-startup "sleep 2 && waybar --config /home/andreas/.config/waybar/config.json --style /home/andreas/.config/waybar/style.css"
```

### NVIDIA Hybrid Graphics
```nix
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = true;
  open = false;
  prime = {
    offload.enable = true;
    offload.enableOffloadCmd = true;
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
};
```

### Zsh History
Must be after oh-my-zsh in config:
```nix
programs.zsh.history = {
  size = 10000;
  save = 10000;
  path = "$HOME/.zsh_history";
};
```

### NixOS Shebang
Scripts must use `#!/usr/bin/env bash` not `#!/bin/bash`

### XDG_CURRENT_DESKTOP
Added to session variables and niri spawn command for proper desktop detection.

## Installed Packages

### System-wide (configuration.nix)
waybar, alacritty, fuzzel, firefox, brave, git, jq, btop, nvtopPackages.full,
mesa-demos, slack, discord/vesktop, ollama, psmisc

### User (home.nix)
ripgrep, fd, eza, bat, fzf, lazygit

## Fonts
- JetBrainsMono Nerd Font
- Iosevka Nerd Font
- Noto fonts + emoji
- Adwaita icon theme (cursor)

## Monitor Layout

```
                    ┌─────────────────────┐
                    │                     │
                    │      DP-5 (32")     │  ┌────────┐
                    │    scale 1.25       │  │ DP-4   │
                    │  3840x2160 logical  │  │ (27")  │
                    │     3072x1728       │  │rotated │
                    └─────────────────────┘  │ 90° CW │
                    ┌─────────────────────┐  │        │
                    │      eDP-1          │  │        │
                    │     (laptop)        │  │        │
                    │     scale 2         │  │        │
                    │  2560x1600 logical  │  └────────┘
                    │     1920x1200       │
                    └─────────────────────┘
```

## Migrated From EndeavourOS
- Brave profiles (copied from mounted /mnt/endeavouros)
- Zsh history
- SSH keys

## Useful References
- [niri wiki](https://yalter.github.io/niri/)
- [Home Manager options](https://nix-community.github.io/home-manager/options.html)
- [NixOS options](https://search.nixos.org/options)
- [Nix packages](https://search.nixos.org/packages)
