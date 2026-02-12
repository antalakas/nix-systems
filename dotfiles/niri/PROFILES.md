# Niri Monitor Profiles

Multiple monitor configurations that can be switched on demand.

## Available Profiles

### `home` - 3 Monitors
- eDP-1: Laptop (bottom, 1920x1200)
- DP-5: 32" horizontal (top center, 3072x1728)
- DP-4: 27" vertical right (1440x2560)

### `office` - 4 Monitors
- eDP-1: Laptop (bottom center)
- DP-6: 27" horizontal center (top)
- DP-8: 27" vertical right
- DP-2: 25" vertical left

## Switch Profiles

```bash
# Show current profile
niri-profile

# Switch to home setup
niri-profile home

# Switch to office setup
niri-profile office

# Reload niri after switching
Mod+Shift+C  # or log out/in
```

## Set Up Office Profile (First Time)

When you're at the office with all 4 monitors connected:

**1. Identify monitor ports:**
```bash
# Connect all monitors, then run:
niri msg outputs

# You'll see output like:
# Output "eDP-1" ... (laptop)
# Output "DP-3" ... (some monitor)
# Output "DP-4" ... (some monitor)
# Output "DP-5" ... (some monitor)
```

**2. Match physical monitors to ports:**

Open a terminal on each monitor and run:
```bash
# On monitor A (27" horizontal center):
echo "This is Monitor A" && sleep 10

# On monitor B (27" vertical right):
echo "This is Monitor B" && sleep 10

# etc.
```

Look at `niri msg outputs` to see which output name corresponds to which monitor.

**3. Update the config:**

Edit `/etc/nixos/dotfiles/niri/config-office.kdl` and replace:
- `PORT_A` with the actual port for 27" horizontal center
- `PORT_B` with the actual port for 27" vertical right
- `PORT_C` with the actual port for 25" vertical left

**4. Rebuild and test:**
```bash
sudo nixos-rebuild switch
niri-profile office
# Mod+Shift+C to reload
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
│    │ │   PORT_A (27") │ │    │
│C   │ │   Horizontal   │ │  B │ (27" vertical)
│25" │ └────────────────┘ │27" │
│    │   ┌──────────┐     │    │
└────┘   │  Laptop  │     └────┘
         └──────────┘
```

## Tips

- Adjust `scale` values in config if text is too small/large
- Adjust positions if monitors don't align perfectly
- Use `transform "90"` or `"270"` to rotate vertical monitors
- Profile switching is instant after niri reload
