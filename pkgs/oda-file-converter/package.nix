{
  lib,
  stdenv,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  qt6,
  libGL,
  libGLU,
  fontconfig,
  freetype,
  libx11,
  libxext,
  libxrender,
  libxcb,
  xcbutilwm,
  xcbutil,
  xcbutilimage,
  xcbutilkeysyms,
  xcbutilrenderutil,
  xcb-util-cursor,
  libxkbcommon,
  libpng,
  zlib,
  glib,
  dbus,
  expat,
}:

let
  version = "27.1.0.0";

  extracted = stdenv.mkDerivation {
    pname = "oda-file-converter-extracted";
    inherit version;

    src = builtins.path {
      path = /etc/nixos/pkgs/oda-file-converter/ODAFileConverter_QT6_lnxX64_8.3dll_27.1.deb;
      name = "ODAFileConverter.deb";
    };

    nativeBuildInputs = [ dpkg ];

    unpackPhase = "true";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      dpkg-deb -x "$src" unpacked
      mkdir -p "$out"
      cp -r unpacked/usr/bin/ODAFileConverter_${version} "$out/app"
    '';
  };

  runScript = writeShellScript "run-oda-file-converter" ''
    export QT_QPA_PLATFORM=xcb
    export QT_PLUGIN_PATH=/usr/lib/qt-6/plugins
    export DISPLAY=''${DISPLAY:-:0}
    exec "${extracted}/app/ODAFileConverter" "$@"
  '';
in
buildFHSEnv {
  name = "ODAFileConverter";

  targetPkgs = pkgs: with pkgs; [
    # Qt6
    qt6.qtbase
    qt6.qtwayland
    qt6.qtsvg
    # Graphics
    libGL
    libGLU
    # X11 / Wayland
    libx11
    libxext
    libxrender
    libxcb
    xcbutilwm
    xcbutil
    xcbutilimage
    xcbutilkeysyms
    xcbutilrenderutil
    xcb-util-cursor
    libxkbcommon
    # System libs
    fontconfig
    freetype
    libpng
    zlib
    glib
    dbus
    expat
  ];

  inherit runScript;

  meta = {
    description = "Convert between .dwg and .dxf file formats";
    homepage = "https://www.opendesign.com/guestfiles/oda-file-converter";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ODAFileConverter";
  };
}
