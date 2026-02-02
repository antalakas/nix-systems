# Niri Setup on NixOS

This documents the niri (Wayland compositor) setup with multi-monitor support and Waybar.

## Hardware Setup

- **eDP-1**: Laptop display (bottom, primary reference point)
- **DP-5**: 32" Dell U3225QE (centered above laptop)
- **DP-4**: 27" Dell P2725QE (right side, rotated 90 degrees clockwise)

## Configuration Files

### System Configuration (`/etc/nixos/`)

**`flake.nix`** - Simple flake using nixpkgs unstable:
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

**`configuration-niri.nix`** - Niri module (imported by configuration.nix):
- Enables `programs.niri`
- Sets Wayland environment variables (`MOZ_ENABLE_WAYLAND`, `NIXOS_OZONE_WL`, `XDG_CURRENT_DESKTOP`)

**`configuration.nix`** key additions:
- `imports = [ ./configuration-niri.nix ]`
- XDG portal for wlroots:
  ```nix
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "wlr" "gtk" ];
  };
  ```
- System packages: `waybar`, `alacritty`, `fuzzel`, `firefox`, `git`, `jq`, `psmisc`

### User Configuration

**`~/.config/niri/config.kdl`** - Niri configuration:
- Multi-monitor layout with positions, scales, and rotation
- Environment export for systemd/dbus portal services:
  ```kdl
  spawn-sh-at-startup "export XDG_CURRENT_DESKTOP=niri && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
  ```
- Waybar autostart:
  ```kdl
  spawn-sh-at-startup "sleep 2 && waybar --config /home/andreas/.config/waybar/config.json --style /home/andreas/.config/waybar/style.css"
  ```

**`~/.config/waybar/config.json`** - Waybar configuration:
- Modules: niri-workspaces, clock, pulseaudio, network, cpu, memory, battery, tray
- Uses custom `niri-workspaces.sh` script

**`~/.config/waybar/niri-workspaces.sh`** - Workspace indicator:
```bash
#!/usr/bin/env bash
active=$(niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.is_focused == true) | .idx' 2>/dev/null)
if [ -n "$active" ]; then echo "󰧨 $active"; else echo "󰧨"; fi
```

## Key Fixes Applied

1. **XDG Portal timeout**: Added `xdg.portal.wlr.enable = true` to NixOS config
2. **Environment not exported to systemd**: Added `dbus-update-activation-environment` spawn command in niri config
3. **Scripts with `/bin/bash`**: Changed shebangs to `#!/usr/bin/env bash` for NixOS compatibility
4. **XDG_CURRENT_DESKTOP not set**: Added to session variables and niri spawn command

## Rebuilding

```bash
sudo nixos-rebuild switch
```

After changes to niri config, either restart niri or run:
```bash
pkill waybar
waybar --config ~/.config/waybar/config.json --style ~/.config/waybar/style.css &
```

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
