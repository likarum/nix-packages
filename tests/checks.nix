{ pkgs }:
let
  inherit (pkgs) lib chatgpt-desktop claude-desktop coroslink claude-code-libsecret sddm-theme-hexa-retro fastflowlm lemonade-server;
in {
  inherit chatgpt-desktop claude-desktop coroslink claude-code-libsecret sddm-theme-hexa-retro
    fastflowlm lemonade-server;

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
  # Sans NPU ni réseau : le binaire démarre, toutes les bibliothèques se résolvent
  # et le greffon XRT est placé là où XRT le cherche (<racine>/lib/x86_64-linux-gnu).
  fastflowlm-smoke = pkgs.runCommand "fastflowlm-smoke" { nativeBuildInputs = [ pkgs.glibc.bin ]; } ''
    export HOME=$TMPDIR
    set -x
    grep -m1 'model name' /proc/cpuinfo; grep -m1 -o 'avx512[a-z_]*' /proc/cpuinfo || true
    ${fastflowlm}/bin/flm --version; echo "rc=$?"
    root=${fastflowlm}/lib/fastflowlm
    test "$(flm=${fastflowlm}/bin/flm; $flm --version)" = "FLM v${fastflowlm.version}"
    ${fastflowlm}/bin/flm --help | grep -q 'validate'
    ${fastflowlm}/bin/flm list | grep -q 'd3:edge'
    test -s ${fastflowlm}/share/flm/xclbins/Gemma3-1B-NPU2/layer.xclbin
    test -e $root/lib/x86_64-linux-gnu/libxrt_driver_xdna.so.2
    # flm-real dépend de tous les moteurs NPU : un seul ldd couvre la fermeture.
    for f in $root/flm-real $root/lib/x86_64-linux-gnu/libxrt_driver_xdna.so.2; do
      if ldd "$f" | grep -q 'not found'; then ldd "$f"; echo "bibliothèque manquante pour $f"; exit 1; fi
    done
    touch $out
  '';
  lemonade-smoke = pkgs.runCommand "lemonade-smoke" { nativeBuildInputs = [ pkgs.curl pkgs.glibc.bin ]; } ''
    export HOME=$TMPDIR
    test "$(${lemonade-server}/bin/lemonade --version)" = "lemonade version ${lemonade-server.version}"
    ${lemonade-server}/bin/lemonade --help | grep -q 'Lemonade CLI'
    for f in ${lemonade-server}/lib/lemonade-server/lemond ${lemonade-server}/lib/lemonade-server/lemonade; do
      if ldd "$f" | grep -q 'not found'; then ldd "$f"; exit 1; fi
    done
    # Serveur local seul (port non standard, boucle locale du bac à sable).
    ${lemonade-server}/bin/lemond --port 13399 > lemond.log 2>&1 &
    pid=$!
    for _ in $(seq 1 30); do
      curl -sf http://127.0.0.1:13399/api/v1/health > health.json && break
      sleep 1
    done
    kill $pid || true
    grep -q '"status":"ok"' health.json || { cat lemond.log; exit 1; }
    touch $out
  '';
}
