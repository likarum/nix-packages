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
    # Copy every icon size upstream ships; the set changes between releases.
    cp -r --no-preserve=mode ${contents}/usr/share/icons $out/share/icons
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
