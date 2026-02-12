#!/usr/bin/env bash
# Switch niri monitor profile
# Usage: niri-profile [home|office]

set -e

PROFILE=$1
CONFIG_DIR="$HOME/.config/niri"

if [ -z "$PROFILE" ]; then
  echo "Usage: niri-profile [home|office]"
  echo ""
  echo "Current profile:"
  if [ -L "$CONFIG_DIR/config.kdl" ]; then
    TARGET=$(readlink "$CONFIG_DIR/config.kdl")
    if [[ "$TARGET" == *"config-home.kdl" ]]; then
      echo "  home"
    elif [[ "$TARGET" == *"config-office.kdl" ]]; then
      echo "  office"
    else
      echo "  unknown"
    fi
  else
    echo "  none (no symlink found)"
  fi
  echo ""
  echo "Available profiles:"
  echo "  home   - 3 monitors (laptop + 32\" + 27\" vertical)"
  echo "  office - 4 monitors (laptop + 27\" horiz + 2 verticals)"
  exit 0
fi

if [ "$PROFILE" != "home" ] && [ "$PROFILE" != "office" ]; then
  echo "Error: Profile must be 'home' or 'office'"
  exit 1
fi

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
