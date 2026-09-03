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

### `igo` - 2 Monitors
- eDP-1: Laptop (bottom, 1920x1200 logical at scale 2)
- DP-1: 24" HP ZR2440w (directly above, 1920x1200 at scale 1.0)

The two outputs are the same logical width, so they stack with no horizontal
offset. The HP is `DP-1` even though the cable is HDMI at the monitor end —
the port it lands on is a DisplayPort one. Worth knowing because getting an
output name wrong is silent: niri does not warn about an `output` block that
matches nothing, it just leaves that panel to auto-placement, which puts it
beside the laptop rather than above it. If the layout looks sideways, check
the names in `niri msg outputs` first.

With two outputs carrying what home spreads over three, the HP takes the role
DP-5 plays there — Cursor on WS 1, Brave/TileDB on WS 2 — and the laptop
absorbs the rest: Slack, Logseq and both terminals on WS 1, Brave/Andreas and
Tutanota on WS 2. Workspace numbers are unchanged, so `Mod+1` and `Mod+2` still
mean the same two sets of windows as in the other profiles.

## Switch Profiles

```bash
# Show current profile
niri-profile

# Switch to home setup
niri-profile home

# Switch to office setup
niri-profile office

# Switch to igo setup
niri-profile igo

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

### Igo Layout
```
┌──────────────┐
│  DP-1  (24") │ HP ZR2440w
│  Horizontal  │ 1920x1200
├──────────────┤
│ eDP-1 Laptop │ 1920x1200 logical
└──────────────┘
```

## Tips

- After editing config files, run `sudo nixos-rebuild switch` so changes are applied (configs come from Nix store)
- Adjust `scale` values in config if text is too small/large
- Adjust positions if monitors don't align perfectly
- Use `transform "90"` or `"270"` to rotate vertical monitors (if upside down, swap between them)
- Profile switching is instant after niri reload (`niri msg action load-config-file` or Mod+Shift+C)
