#!/usr/bin/env bash
# Switch niri monitor profile
# Usage: niri-profile [home|office|igo]

set -e

PROFILE=$1
CONFIG_DIR="$HOME/.config/niri"

if [ -z "$PROFILE" ]; then
  echo "Usage: niri-profile [home|office|igo]"
  echo ""
  echo "Current profile:"
  if [ -L "$CONFIG_DIR/config.kdl" ]; then
    TARGET=$(readlink "$CONFIG_DIR/config.kdl")
    case "$TARGET" in
      *config-home.kdl)   echo "  home" ;;
      *config-office.kdl) echo "  office" ;;
      *config-igo.kdl)    echo "  igo" ;;
      *)                  echo "  unknown" ;;
    esac
  else
    echo "  none (no symlink found)"
  fi
  echo ""
  echo "Available profiles:"
  echo "  home   - 3 monitors (laptop + 32\" + 27\" vertical)"
  echo "  office - 4 monitors (laptop + 27\" horiz + 2 verticals)"
  echo "  igo    - 2 monitors (laptop + 24\" HP ZR2440w above it)"
  exit 0
fi

case "$PROFILE" in
  home|office|igo) ;;
  *)
    echo "Error: Profile must be 'home', 'office' or 'igo'"
    exit 1
    ;;
esac

# Remove old symlink/file if exists
rm -f "$CONFIG_DIR/config.kdl"

# Create symlink to the selected profile
ln -s "$CONFIG_DIR/config-$PROFILE.kdl" "$CONFIG_DIR/config.kdl"

echo "✅ Switched to '$PROFILE' profile"
echo "🔄 Reload niri with: niri msg action load-config-file"
echo "   (or Mod+Shift+C, or log out/in)"

# Validate the config
if command -v niri >/dev/null 2>&1; then
  echo ""
  echo "Validating config..."
  niri validate && echo "✅ Config is valid" || echo "⚠️  Config has errors"
fi
