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
| `wireguard-secrets.nix` | WireGuard VPN config (gitignored) |
| `dotfiles/` | Actual dotfile contents managed by Home Manager |
| `templates/` | Flake templates for new projects |

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
mesa-demos, slack, discord, ollama, psmisc, logseq, networkmanagerapplet,
grim, slurp, satty, wl-clipboard

### User (home.nix)
ripgrep, fd, eza, bat, fzf, lazygit, kubectl, kubectx, k9s, stern,
aws-vault, sops, age, yq-go, pixi

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

## WireGuard VPN

NetworkManager-managed WireGuard connection in `wireguard-secrets.nix` (gitignored).

```bash
# Connect/disconnect
nmcli connection up tiledb-wg
nmcli connection down tiledb-wg
```

Also available via nm-applet tray icon.

## Bluetooth Pairing

When pairing a new device via `bluetoothctl`:

```bash
bluetoothctl
power on
agent on
default-agent
scan on
# wait for device to appear, then:
scan off
pair <MAC>          # e.g. pair 34:88:5D:12:AB:CD
trust <MAC>
connect <MAC>
```

Example with a real MAC: `pair 34:88:5D:12:AB:CD` then `trust` and `connect` with the same address.

## Screenshots (Mod+A)

Wayland screenshot tools: grim, slurp, satty

| Key | Action |
|-----|--------|
| `Mod+A` | Region select with annotation (Flameshot-like) |
| `Mod+Shift+A` | Full screen with annotation |
| `Mod+Ctrl+A` | Quick full screen (saves to ~/Pictures/Screenshots/) |
| `Mod+Alt+A` | Focused window only |

## Dev Environment Strategy

**Global tools** (always available via home.nix):
- k8s: kubectl, kubectx/kubens, k9s, stern
- secrets: aws-vault, sops, age
- data: yq-go
- env: direnv + nix-direnv, pixi

**Per-project flakes** (pinned versions where drift matters):
- Use `templates/` for starting new projects
- `.envrc` with `use flake` auto-activates environment on cd

### Templates

```bash
# Python project with pixi
cp -r /etc/nixos/templates/python-pixi ~/workspace/my-project
cd ~/workspace/my-project && direnv allow
pixi init && pixi add python

# Infrastructure/K8s project
cp -r /etc/nixos/templates/infra-k8s ~/workspace/my-infra
cd ~/workspace/my-infra && direnv allow
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
