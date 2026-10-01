{ pkgs }:
let
  inherit (pkgs) lib chatgpt-desktop claude-desktop coroslink claude-code-libsecret sddm-theme-hexa-retro;
in {
  inherit chatgpt-desktop claude-desktop coroslink claude-code-libsecret sddm-theme-hexa-retro;

  update-validation = pkgs.runCommand "update-validation" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    export PYTHONDONTWRITEBYTECODE=1
    python -m unittest discover -s ${../.}/tests -p 'test_*.py'
    touch $out
  '';
  workflows = pkgs.runCommand "workflow-validation" { nativeBuildInputs = [ pkgs.actionlint ]; } ''
    actionlint ${../.github/workflows/check.yml} ${../.github/workflows/update.yml}
    touch $out
  '';
  chatgpt-store-copies = pkgs.runCommand "chatgpt-store-copies" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${../pkgs/chatgpt-desktop/nix/store-copies-test.js} ${../pkgs/chatgpt-desktop/nix/store-copies.js}
    touch $out
  '';
  chatgpt-version = pkgs.runCommand "chatgpt-version" { nativeBuildInputs = [ pkgs.jq ]; } ''
    test "$(jq -r .version ${chatgpt-desktop}/lib/chatgpt/resources/linux-package-metadata.json)" = "${chatgpt-desktop.version}"
    touch $out
  '';
  chatgpt-asar = pkgs.runCommand "chatgpt-asar" { nativeBuildInputs = [ pkgs.asar ]; } ''
    archive=${chatgpt-desktop}/lib/chatgpt/resources/app.asar
    asar extract-file "$archive" .vite/build/early-bootstrap.js
    asar extract-file "$archive" .vite/build/worker.js
    asar extract-file "$archive" node_modules/@parcel/watcher/node_modules/detect-libc/lib/filesystem.js
    grep -q 'Prepended by the chatgpt-desktop Nix package' early-bootstrap.js
    grep -q 'Prepended by the chatgpt-desktop Nix package' worker.js
    grep -q "LDD_PATH = '${builtins.storeDir}/.*/bin/ldd'" filesystem.js
    # Avoid grep -q + pipefail/SIGPIPE on this large archive listing.
    asar list --is-pack "$archive" > archive-files
    grep -q '^unpack : /node_modules/better-sqlite3/build/Release/better_sqlite3.node$' archive-files
    touch $out
  '';
  claude-libsecret = pkgs.runCommand "claude-libsecret" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    # Exercise the dlopen that motivated the wrapper, not a version-string test.
    LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.libsecret ]} \
      python -c 'import ctypes; ctypes.CDLL("libsecret-1.so.0")'
    test -x ${claude-code-libsecret}/bin/claude
    touch $out
  '';
  theme-assets = pkgs.runCommand "sddm-theme-assets" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    theme=${sddm-theme-hexa-retro}/share/sddm/themes/hexa_retro
    test -s "$theme/Main.qml"
    test -s "$theme/metadata.desktop"
    grep -qx 'QtVersion=6' "$theme/metadata.desktop"
    test "$(magick identify "$theme/hexa_retro.gif" | wc -l)" -eq 90
    touch $out
  '';
}
