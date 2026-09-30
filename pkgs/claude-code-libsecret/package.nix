{ lib, symlinkJoin, makeBinaryWrapper, libsecret, claude-code }:
# Preserve Claude Code's upstream package; only make its dlopen dependency visible.
symlinkJoin {
  name = "claude-code-libsecret";
  paths = [ claude-code ];
  nativeBuildInputs = [ makeBinaryWrapper ];
  postBuild = ''
    wrapProgram $out/bin/claude \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libsecret ]}
  '';
  meta = claude-code.meta // { mainProgram = "claude"; };
}
