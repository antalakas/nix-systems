# Graphical profile: the niri Wayland session and the pieces every host with a
# screen needs. The mirror image of modules/server.nix — a host imports one or
# the other, never both.
#
# Extracted from hosts/nixos/default.nix when `scribe` was added, and imported
# only by that host so far. The laptop still carries its own copy of everything
# below, so the two can drift; migrating it is deliberately a separate job,
# because that config needs `--impure` and an out-of-tree import, and so cannot
# be evaluated from anywhere but the machine itself. Until that happens, a
# change here has to be mirrored by hand into hosts/nixos/default.nix.
#
# What deliberately did *not* move: NVIDIA/PRIME, printing, flatpak, ollama,
# 1Password, YubiKey, spacenavd, CUDA. Those are one machine's hardware and
# habits rather than a shared desktop, and putting them here would push a
# discrete-GPU stack onto a laptop that has no discrete GPU.

{ config, pkgs, lib, ... }:

{
  # ─────────────────────────────────────────────────────────────
  # Session
  # ─────────────────────────────────────────────────────────────
  programs.niri.enable = true;

  # greetd + tuigreet: a text greeter, so there is no second desktop stack
  # installed purely to log in. `--remember` and `--remember-session` mean the
  # usual path is a password and Enter.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd niri-session";
      user = "greeter";
    };
  };

  # XWayland for the apps that still need it. niri does not embed an X server,
  # so without this Electron/Java/Steam-era clients simply fail to start rather
  # than falling back to anything.
  environment.variables = {
    MOZ_ENABLE_WAYLAND = "1";
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_CURRENT_DESKTOP = "niri";
  };

  # Keymap for the console and for XWayland clients. The Wayland side is set
  # separately in the niri KDL (`input.keyboard.xkb`, us,gr with alt+shift to
  # toggle) — niri reads its own config rather than this, so the two are set in
  # two places on purpose and only this one reaches a bare TTY.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # ─────────────────────────────────────────────────────────────
  # Graphics, portals, and the bits Wayland clients assume exist
  # ─────────────────────────────────────────────────────────────
  hardware.graphics.enable = true;
  security.polkit.enable = true;
  services.dbus.enable = true;

  # Chromium-based browsers (Brave) and Electron apps out of the nix store
  # build their sandbox on unprivileged user namespaces; without this they
  # either refuse to start or run with the sandbox off.
  security.unprivilegedUsernsClone = true;

  # Deliberately no `config` block: programs.niri already sets
  # xdg.portal.config.niri = [ "gnome" "gtk" ] plus the gnome portal, and
  # defining config.niri here replaces that wholesale. ScreenCast must land on
  # the gnome backend — niri implements the org.gnome.Mutter.ScreenCast D-Bus
  # API that backend drives and does not work with xdg-desktop-portal-wlr, so
  # routing it elsewhere silently kills browser screen sharing.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # ─────────────────────────────────────────────────────────────
  # Audio
  # ─────────────────────────────────────────────────────────────
  # New here rather than lifted from the laptop: nothing in this repo
  # configured sound at all before `scribe`. The niri binds shipped in
  # dotfiles/niri/*.kdl drive volume through `wpctl`, which is WirePlumber, so
  # the keys were bound to a command that did not exist. rtkit is what lets the
  # audio threads take realtime priority; without it PipeWire runs but crackles
  # under load.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ─────────────────────────────────────────────────────────────
  # Screen locking
  # ─────────────────────────────────────────────────────────────
  # swaylock is bound to Super+Alt+L in every niri profile but was installed by
  # nothing, so that bind was a no-op. The PAM entry is the half that is easy
  # to miss and impossible to diagnose from the lock screen: swaylock
  # authenticates against a PAM service of its own name, and with no such
  # service it locks correctly and then refuses every correct password. On a
  # machine that leaves the house that is the difference between a lock screen
  # and a brick.
  security.pam.services.swaylock = { };

  # ─────────────────────────────────────────────────────────────
  # Packages
  # ─────────────────────────────────────────────────────────────
  # The CLI baseline is in modules/common.nix; this is what only a screen needs.
  environment.systemPackages = with pkgs; [
    alacritty
    fuzzel # app launcher (Mod+D)
    waybar
    firefox
    brave
    xwayland-satellite
    networkmanagerapplet # nm-applet, the tray icon niri spawns at startup
    adwaita-icon-theme

    # Screen locking and media keys — both bound in dotfiles/niri/*.kdl.
    swaylock
    playerctl

    # Screenshots (Mod+A and friends)
    grim # capture
    slurp # region select
    satty # annotate
    wl-clipboard

    brightnessctl # XF86MonBrightness* binds
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    # Iosevka is the one that is load-bearing rather than decorative:
    # home/alacritty.nix and the fuzzel config both name "Iosevka Nerd Font",
    # and a missing font there degrades to a fallback with no Nerd Font glyphs,
    # which is what makes a p10k prompt render as boxes.
    nerd-fonts.iosevka
  ];
}
