# Niri Keybindings Reference

**Mod** = Super (Windows key) when running on TTY

Press `Mod+Shift+/` (or `Mod+?`) to show the hotkey overlay.

---

## Applications

| Keybinding | Action |
|------------|--------|
| `Mod+Enter` | Open terminal (Alacritty) |
| `Mod+D` | Open app launcher (Fuzzel) |
| `Super+Alt+L` | Lock screen (swaylock) |
| `Super+Alt+S` | Toggle screen reader (Orca) |

---

## Keyboard Layout

| Keybinding | Action |
|------------|--------|
| `Alt+Shift` | Switch between US and Greek keyboard layouts |

---

## Window Focus

| Keybinding | Action |
|------------|--------|
| `Mod+Left` / `Mod+H` | Focus column left |
| `Mod+Right` / `Mod+L` | Focus column right |
| `Mod+Up` / `Mod+K` | Focus window up (in column) |
| `Mod+Down` / `Mod+J` | Focus window down (in column) |
| `Mod+Home` | Focus first column |
| `Mod+End` | Focus last column |

---

## Window Movement

| Keybinding | Action |
|------------|--------|
| `Mod+Ctrl+Left` / `Mod+Ctrl+H` | Move column left |
| `Mod+Ctrl+Right` / `Mod+Ctrl+L` | Move column right |
| `Mod+Ctrl+Up` / `Mod+Ctrl+K` | Move window up (in column) |
| `Mod+Ctrl+Down` / `Mod+Ctrl+J` | Move window down (in column) |
| `Mod+Ctrl+Home` | Move column to first |
| `Mod+Ctrl+End` | Move column to last |

---

## Window Management

| Keybinding | Action |
|------------|--------|
| `Mod+Q` | Close window |
| `Mod+F` | Maximize column |
| `Mod+Shift+F` | Fullscreen window |
| `Mod+Ctrl+F` | Expand column to available width |
| `Mod+C` | Center column |
| `Mod+Ctrl+C` | Center all visible columns |
| `Mod+V` | Toggle floating |
| `Mod+Shift+V` | Switch focus between floating and tiling |
| `Mod+W` | Toggle tabbed column display |

---

## Window Sizing

| Keybinding | Action |
|------------|--------|
| `Mod+R` | Cycle preset column widths (1/3, 1/2, 2/3) |
| `Mod+Shift+R` | Cycle preset window heights |
| `Mod+Ctrl+R` | Reset window height |
| `Mod+Minus` | Decrease column width by 10% |
| `Mod+Equal` | Increase column width by 10% |
| `Mod+Shift+Minus` | Decrease window height by 10% |
| `Mod+Shift+Equal` | Increase window height by 10% |

---

## Column Stacking

| Keybinding | Action |
|------------|--------|
| `Mod+[` | Consume or expel window left |
| `Mod+]` | Consume or expel window right |
| `Mod+,` | Consume window from right into column |
| `Mod+.` | Expel bottom window from column |

---

## Workspaces (Per Monitor)

| Keybinding | Action |
|------------|--------|
| `Mod+1` to `Mod+9` | Focus workspace 1-9 on current monitor |
| `Mod+Page_Up` / `Mod+I` | Focus workspace above |
| `Mod+Page_Down` / `Mod+U` | Focus workspace below |
| `Mod+O` | Toggle overview (all workspaces) |

---

## Move Windows to Workspace

| Keybinding | Action |
|------------|--------|
| `Mod+Ctrl+1` to `Mod+Ctrl+9` | Move column to workspace 1-9 |
| `Mod+Ctrl+Page_Up` / `Mod+Ctrl+I` | Move column to workspace above |
| `Mod+Ctrl+Page_Down` / `Mod+Ctrl+U` | Move column to workspace below |

---

## Reorder Workspaces

| Keybinding | Action |
|------------|--------|
| `Mod+Shift+Page_Up` / `Mod+Shift+I` | Move workspace up |
| `Mod+Shift+Page_Down` / `Mod+Shift+U` | Move workspace down |

---

## Monitor Focus

| Keybinding | Action |
|------------|--------|
| `Mod+Shift+Left` / `Mod+Shift+H` | Focus monitor left |
| `Mod+Shift+Right` / `Mod+Shift+L` | Focus monitor right |
| `Mod+Shift+Up` / `Mod+Shift+K` | Focus monitor up |
| `Mod+Shift+Down` / `Mod+Shift+J` | Focus monitor down |

---

## Move Windows to Monitor

| Keybinding | Action |
|------------|--------|
| `Mod+Shift+Ctrl+Left` / `Mod+Shift+Ctrl+H` | Move column to monitor left |
| `Mod+Shift+Ctrl+Right` / `Mod+Shift+Ctrl+L` | Move column to monitor right |
| `Mod+Shift+Ctrl+Up` / `Mod+Shift+Ctrl+K` | Move column to monitor up |
| `Mod+Shift+Ctrl+Down` / `Mod+Shift+Ctrl+J` | Move column to monitor down |

---

## Mouse Wheel (with Mod)

| Keybinding | Action |
|------------|--------|
| `Mod+WheelUp/Down` | Switch workspaces |
| `Mod+Ctrl+WheelUp/Down` | Move column to workspace |
| `Mod+WheelLeft/Right` | Focus column left/right |
| `Mod+Ctrl+WheelLeft/Right` | Move column left/right |
| `Mod+Shift+WheelUp/Down` | Focus column left/right |

---

## Media & Hardware Keys

| Keybinding | Action |
|------------|--------|
| `XF86AudioRaiseVolume` | Volume up 10% |
| `XF86AudioLowerVolume` | Volume down 10% |
| `XF86AudioMute` | Toggle mute |
| `XF86AudioMicMute` | Toggle mic mute |
| `XF86AudioPlay` | Play/pause media |
| `XF86AudioStop` | Stop media |
| `XF86AudioPrev` | Previous track |
| `XF86AudioNext` | Next track |
| `XF86MonBrightnessUp` | Brightness up 10% |
| `XF86MonBrightnessDown` | Brightness down 10% |

---

## Screenshots

| Keybinding | Action |
|------------|--------|
| `Print` | Screenshot (interactive) |
| `Ctrl+Print` | Screenshot current screen |
| `Alt+Print` | Screenshot current window |

Screenshots saved to: `~/Pictures/Screenshots/`

---

## System

| Keybinding | Action |
|------------|--------|
| `Mod+Shift+/` | Show hotkey overlay |
| `Mod+Shift+E` | Quit niri (with confirmation) |
| `Ctrl+Alt+Delete` | Quit niri (with confirmation) |
| `Mod+Shift+P` | Power off monitors |
| `Mod+Escape` | Toggle keyboard shortcut inhibit |

---

## Command Line

You can also trigger actions via command line:

```bash
# Move window to workspace 3
niri msg action move-column-to-workspace 3

# Move to next monitor
niri msg action move-column-to-monitor-right

# Focus workspace 2
niri msg action focus-workspace 2

# Toggle overview
niri msg action toggle-overview

# List all available actions
niri msg action --help
```
