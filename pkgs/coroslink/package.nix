{ lib, fetchurl, appimageTools }:
let
  sources = lib.importJSON ./sources.json;
  pname = "coroslink";
  inherit (sources) version;
  src = fetchurl { inherit (sources.sources.x86_64-linux) url hash; };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraPkgs = p: [ p.yt-dlp p.ffmpeg ];
  extraInstallCommands = ''
    install -Dm444 ${contents}/${pname}.desktop \
      $out/share/applications/${pname}.desktop
    # Preserve upstream's existing launch flags, including --no-sandbox.
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    install -Dm444 \
      ${contents}/usr/share/icons/hicolor/1024x1024/apps/${pname}.png \
      $out/share/icons/hicolor/1024x1024/apps/${pname}.png
  '';
  passthru.updateScript = [ "python3" "scripts/update.py" "coroslink" ];
  meta = {
    description = "Unofficial COROS companion, including Watch Face Studio";
    homepage = "https://github.com/JunAkerBuilds/CorosLink";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
