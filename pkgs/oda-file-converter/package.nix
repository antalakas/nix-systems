{
  lib,
  stdenv,
  dpkg,
  buildFHSEnv,
  qt6,
  libGL,
  fontconfig,
  freetype,
  xorg,
}:

let
  version = "27.1.0.0";

  extracted = stdenv.mkDerivation {
    pname = "oda-file-converter-extracted";
    inherit version;

    src = ./ODAFileConverter_QT6_lnxX64_8.3dll_27.1.deb;

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
in
buildFHSEnv {
  name = "ODAFileConverter";

  targetPkgs = pkgs: with pkgs; [
    qt6.qtbase
    qt6.qtwayland
    libGL
    fontconfig
    freetype
    xorg.libX11
    xorg.libXext
    xorg.libXrender
  ];

  runScript = "${extracted}/app/ODAFileConverter";

  meta = {
    description = "Convert between .dwg and .dxf file formats";
    homepage = "https://www.opendesign.com/guestfiles/oda-file-converter";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ODAFileConverter";
  };
}
