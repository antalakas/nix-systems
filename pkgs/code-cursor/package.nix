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
      url = "https://downloads.cursor.com/production/4f02290ccd9304f0e6bf8ee85f6e9106f02ac1f7/linux/x64/Cursor-3.13.10-x86_64.AppImage";
      hash = "sha256-pZq2rQnIbFLejOkK2y0GZEVRmuNKZvI+oxaviK/vpXQ=";
    };
  };

  source =
    sources.${hostPlatform.system}
      or (throw "Local Cursor 3 package is only defined for ${hostPlatform.system}");
in
buildVscode rec {
  inherit useVSCodeRipgrep;
  version = "3.13.10";
  vscodeVersion = "1.128.0";
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
