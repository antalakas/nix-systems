{
  lib,
  stdenv,
  buildVscode,
  fetchurl,
  appimageTools,
  undmg,
  writeShellScript,
  commandLineArgs ? "",
  useVSCodeRipgrep ? stdenv.hostPlatform.isDarwin,
}:

let
  inherit (stdenv) hostPlatform;
  finalCommandLineArgs = "--update=false " + commandLineArgs;

  sources = {
    x86_64-linux = fetchurl {
      url = "https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/3.0";
      hash = "sha256-SdlcESipjWnLNPGf4sBxb28cpQ36uHoRzGsPC9X72Ww=";
    };
  };

  source =
    sources.${hostPlatform.system}
      or (throw "Local Cursor 3 package is only defined for ${hostPlatform.system}");
in
buildVscode rec {
  inherit useVSCodeRipgrep;
  version = "3.0";
  vscodeVersion = "1.105.1";
  commandLineArgs = finalCommandLineArgs;

  pname = "cursor";

  executableName = "cursor";
  longName = "Cursor";
  shortName = "cursor";
  libraryName = "cursor";
  iconName = "cursor";

  src =
    if hostPlatform.isLinux then
      appimageTools.extract {
        inherit pname version;
        src = source;
      }
    else
      source;

  extraNativeBuildInputs = lib.optionals hostPlatform.isDarwin [ undmg ];

  sourceRoot =
    if hostPlatform.isLinux then "${pname}-${version}-extracted/usr/share/cursor" else "Cursor.app";

  tests = { };

  updateScript = writeShellScript "update-code-cursor" ''
    echo "Update this package manually by bumping version, URL, and hash."
  '';

  # Cursor has no wrapper script.
  patchVSCodePath = false;

  meta = {
    description = "AI-powered code editor built on VS Code";
    homepage = "https://cursor.com";
    changelog = "https://cursor.com/changelog";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "cursor";
  };
}
