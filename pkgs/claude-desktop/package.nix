{
  lib,
  fetchurl,
  stdenvNoCC,
  buildFHSEnv,

  ### Tools
  dpkg,
  autoPatchelfHook,
  makeWrapper,

  ### Electron/Chromium
  nss,
  nspr,
  mesa,
  alsa-lib,
  libxkbcommon,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  at-spi2-atk,
  at-spi2-core,
  cups,
  dbus,
  gtk3,
  pango,
  cairo,
  expat,
  glib,
  systemd,

  ### OpenGL dispatch (Chromium dlopens libEGL.so.1 at runtime)
  libglvnd,

  ### For virtiofsd
  libseccomp,
  libcap_ng,

  ### For keyring support
  libsecret,

  ### For Cowork QEMU
  qemu_kvm,
  OVMF,

  ### For Cowork VM virtiofsd (nixpkgs instead of bundled)
  virtiofsd,

  ### For ASAR patching
  asar,

  ### For extensions
  python3,
  nodejs,

  ### Sso login
  xdg-utils,

  ### Optional host tools Cowork / Code features may exec by absolute path
  git,
  openssh,
  procps,

  ### Force a specific password store backend (e.g. "gnome-libsecret" for Hyprland /
  ### other non-GNOME sessions where Chromium does not auto-select a backend).
  ### Leave null on GNOME/KDE with a working Secret Service / portal.
  sources ? lib.importJSON ./sources.json,
  passwordStore ? null,

  ### DELTA LOCAL (absent du PR amont #537215) — voir aussi le commentaire sur
  ### wrapProgram plus bas. Navigateur utilisé pour le login SSO. Nécessaire sur
  ### les sessions que xdg-open ne reconnaît pas (Hyprland, niri, sway…), où il
  ### tombe dans open_generic et cherche des binaires par NOM (x-www-browser,
  ### firefox, chromium, google-chrome…) : aucun n'existe dans l'env FHS, donc
  ### le clic sur « Log in » ne fait strictement rien.
  ### On passe un chemin absolu du store via $BROWSER : /nix/store est monté
  ### dans le bwrap, donc pas besoin de l'ajouter à targetPkgs. Le navigateur
  ### lancé depuis le sandbox partage $HOME, donc il transmet simplement l'URL
  ### à l'instance déjà ouverte sur l'hôte.
  browser ? null,
}:

let
  ### Libraries Chromium may dlopen rather than DT_NEEDED-link
  runtimeLibs = [
    libsecret
    libglvnd
  ];

  ### Arguments wrapProgram optionnels. Assemblés en liste puis joints sur UNE
  ### ligne : un `lib.optionalString` avec une chaîne multi-lignes injecterait
  ### un saut de ligne qui terminerait la commande wrapProgram, et l'argument
  ### suivant repartirait comme une commande shell à part entière.
  extraWrapArgs =
    lib.optional (passwordStore != null) ''--add-flags "--password-store=${passwordStore}"''
    ++ lib.optional (browser != null) "--set-default BROWSER ${lib.getExe browser}";

  unwrapped = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "claude-desktop";
    version = sources.version;

    src = fetchurl {
      inherit (sources.sources.${stdenvNoCC.hostPlatform.system}) url hash;
    };

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
      makeWrapper
      asar
    ];

    buildInputs = [
      ### Electron/Chromium
      nss
      nspr
      mesa
      libglvnd
      alsa-lib
      libxkbcommon
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      at-spi2-atk
      at-spi2-core
      cups
      dbus
      gtk3
      pango
      cairo
      expat
      glib
      systemd

      ### Bundled virtiofsd
      libseccomp
      libcap_ng

      ### For keyring support
      libsecret

      ### For Cowork QEMU
      qemu_kvm
      OVMF.fd

      ### For extensions
      python3
      nodejs

      ### For sso login
      xdg-utils
    ];

    unpackPhase = ''
      runHook preUnpack

      dpkg-deb --fsys-tarfile $src | tar --extract

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      mv usr/* $out

      runHook postInstall
    '';

    postFixup = ''
      # Patch app.asar for Cowork VM paths (OVMF firmware + virtiofsd).
      # Use --replace-fail so upstream string drift fails the build instead of
      # silently shipping a broken Cowork VM.
      asarRoot=$out/lib/claude-desktop/resources
      if [ ! -f "$asarRoot/app.asar" ]; then
        echo "error: expected app.asar at $asarRoot/app.asar" >&2
        exit 1
      fi

      work=$(mktemp -d)
      asar extract "$asarRoot/app.asar" "$work/contents"

      cd "$work/contents"

      # the chunk carrying the Cowork VM literals rotates its name every release
      coworkJs=$(grep -rl '/usr/libexec/virtiofsd' .vite/build)
      if [ "$(printf '%s\n' "$coworkJs" | wc -l)" -ne 1 ]; then
        echo "expected exactly one file with the Cowork literals, got: $coworkJs" >&2
        exit 1
      fi

      substituteInPlace "$coworkJs" \
        --replace-fail \
        '["/usr/share/OVMF/OVMF_CODE_4M.fd","/usr/share/OVMF/OVMF_CODE.fd"]' \
        '["${OVMF.fd}/FV/OVMF_CODE.fd"]' \
        --replace-fail \
        '["/usr/libexec/virtiofsd","/usr/bin/virtiofsd"]' \
        '["${virtiofsd}/bin/virtiofsd"]'

      cd - >/dev/null

      asar pack "$work/contents" "$work/app.asar" --unpack "{**/*.node,**/spawn-helper}"
      cp -f "$work/app.asar" "$asarRoot/app.asar"
      if [ -d "$work/app.asar.unpacked" ]; then
        rm -rf "$asarRoot/app.asar.unpacked"
        cp -r "$work/app.asar.unpacked" "$asarRoot/app.asar.unpacked"
      fi
      rm -rf "$work"

      wrapProgram $out/bin/claude-desktop \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:/run/opengl-driver-32/lib \
        --prefix PATH : ${
          lib.makeBinPath [
            python3
            nodejs
            xdg-utils
            git
            openssh
            procps
          ]
        } ${lib.concatStringsSep " " extraWrapArgs}
    '';

    passthru.updateScript = [ "python3" "scripts/update.py" "claude-desktop" ];

    meta = {
      description = "Desktop application for Claude.ai";
      homepage = "https://claude.ai/download";
      license = lib.licenses.unfree;
      mainProgram = "claude-desktop";
      maintainers = with lib.maintainers; [
        minegameYTB
        ooonea
        diwangs
      ];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  });

  fhsEnv = buildFHSEnv {
    pname = "claude-desktop-fhsenv";
    inherit (unwrapped) version;

    targetPkgs =
      pkgs: with pkgs; [
        unwrapped
        glibc
        qemu_kvm
        python3
        nodejs
        libsecret
        libglvnd
        mesa
        virtiofsd
        git
        openssh
        procps
      ];

    extraBuildCommands = ''
      ### OVMF firmware
      mkdir -p "$out/usr/share/OVMF"
      ln -s ${OVMF.fd}/FV/OVMF_CODE.fd  "$out/usr/share/OVMF/OVMF_CODE.fd"
      ln -s ${OVMF.fd}/FV/OVMF_CODE.fd  "$out/usr/share/OVMF/OVMF_CODE_4M.fd"
      ln -s ${OVMF.fd}/FV/OVMF_VARS.fd  "$out/usr/share/OVMF/OVMF_VARS.fd"
      ln -s ${OVMF.fd}/FV/OVMF_VARS.fd  "$out/usr/share/OVMF/OVMF_VARS_4M.fd"

      ### virtiofsd fallback paths
      mkdir -p "$out/usr/libexec" "$out/usr/bin"
      ln -sf ${virtiofsd}/bin/virtiofsd "$out/usr/libexec/virtiofsd"
      ln -sf ${virtiofsd}/bin/virtiofsd "$out/usr/bin/virtiofsd"

      ### Absolute-path helpers some app code still probes under /usr/bin
      mkdir -p "$out/usr/bin"
      ln -sf ${lib.getExe git} "$out/usr/bin/git"
      ln -sf ${openssh}/bin/ssh "$out/usr/bin/ssh"
      ln -sf ${procps}/bin/pgrep "$out/usr/bin/pgrep"
    ''
    + lib.optionalString (stdenvNoCC.hostPlatform.isAarch64) ''
      ### AAVMF firmware (used when process.arch = "arm64")
      mkdir -p "$out/usr/share/AAVMF"
      ln -s ${OVMF.fd}/FV/AAVMF_CODE.fd  "$out/usr/share/AAVMF/AAVMF_CODE.fd"
      ln -s ${OVMF.fd}/FV/AAVMF_VARS.fd  "$out/usr/share/AAVMF/AAVMF_VARS.fd"
    '';

    extraBwrapArgs = [
      "--dev-bind-try /dev/kvm /dev/kvm"
      "--dev-bind-try /dev/vhost-vsock /dev/vhost-vsock"
      "--dev-bind-try /dev/vhost-net /dev/vhost-net"
      "--dev-bind-try /dev/net/tun /dev/net/tun"
    ];

    extraInstallCommands = ''
      mkdir -p "$out/share"
      ln -s ${unwrapped}/share/* "$out/share/"
    '';

    runScript = "${unwrapped}/bin/claude-desktop";

    ### Avoid orphaned Electron after the launcher / nix run exits
    dieWithParent = true;
  };
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit (unwrapped) version;
  strictDeps = true;
  __structuredAttrs = true;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$out/bin" "$out/share"
    ln -s ${fhsEnv}/bin/claude-desktop-fhsenv "$out/bin/claude-desktop"
    ln -s ${fhsEnv}/share/* "$out/share/"
  '';

  inherit (unwrapped) meta;
  passthru = unwrapped.passthru // {
    inherit unwrapped fhsEnv;
  };
}
