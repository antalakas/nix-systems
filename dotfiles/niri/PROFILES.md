# Niri Monitor Profiles

Multiple monitor configurations that can be switched on demand.

## Available Profiles

### `home` - 3 Monitors
- eDP-1: Laptop (bottom, 1920x1200)
- DP-5: 32" horizontal (top center, 3072x1728)
- DP-4: 27" vertical right (1440x2560)

### `office` - 4 Monitors
- eDP-1: Laptop (bottom center, under DP-6)
- DP-6: 27" horizontal center (top) – A
- DP-2: 27" vertical right – B
- DP-8: 25" vertical left – C

Layout: **C (left) – A (center) – B (right)** + laptop below A

## Switch Profiles

```bash
# Show current profile
niri-profile

# Switch to home setup
niri-profile home

# Switch to office setup
niri-profile office

# Reload niri after switching
niri msg action load-config-file   # or Mod+Shift+C, or log out/in
```

## Layout Details

### Home Layout
```
        ┌─────────────────┐
        │   DP-5 (32")    │
        │   Horizontal    │
        └─────────────────┘
                           ┌────┐
                           │DP-4│ (27" vertical)
                           │ │  │
                           │ │  │
┌──────────────┐          └────┘
│ eDP-1 Laptop │
└──────────────┘
```

### Office Layout
```
┌────┐ ┌────────────────┐ ┌────┐
│    │ │   DP-6 (27")   │ │    │
│DP-8│ │   Horizontal   │ │DP-2│ (27" vertical)
│25" │ └────────────────┘ │27" │
│    │   ┌──────────┐     │    │
└────┘   │  Laptop  │     └────┘
         └──────────┘
```

## Tips

- After editing config files, run `sudo nixos-rebuild switch` so changes are applied (configs come from Nix store)
- Adjust `scale` values in config if text is too small/large
- Adjust positions if monitors don't align perfectly
- Use `transform "90"` or `"270"` to rotate vertical monitors (if upside down, swap between them)
- Profile switching is instant after niri reload (`niri msg action load-config-file` or Mod+Shift+C)
