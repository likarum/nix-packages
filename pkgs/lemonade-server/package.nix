{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, dpkg
, jq
, openssl
, zlib
, zstd
, libdrm
, gcc
, fastflowlm
}:
let
  sources = lib.importJSON ./sources.json;
  src = fetchurl { inherit (sources.sources.x86_64-linux) url hash; };
  # Ressources complètes (interface web, schémas, valeurs par défaut) : seul le
  # .deb Debian 13 de la même version les contient. Les binaires de ce .deb ne
  # sont pas utilisés (bibliothèques Debian), uniquement ses données.
  resourcesDeb = fetchurl { inherit (sources.resources.x86_64-linux) url hash; };
in
stdenv.mkDerivation {
  pname = "lemonade-server";
  inherit (sources) version;
  inherit src;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper dpkg jq ];
  buildInputs = [
    openssl
    zlib
    zstd
    libdrm # libdrm_amdgpu, chargée par lemond pour la télémétrie
    gcc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;

  # L'archive « embeddable » officielle fournit lemond et lemonade (liés à
  # glibc 2.38) ; les ressources viennent du .deb. Pas d'application de bureau,
  # ni de pile ROCm/Vulkan/génération d'images.
  installPhase = ''
    runHook preInstall
    root=$out/lib/lemonade-server
    mkdir -p $root $out/bin $out/share/doc/lemonade-server
    install -Dm755 lemond lemonade -t $root
    dpkg-deb -x ${resourcesDeb} deb
    cp -a deb/usr/share/lemonade-server/resources $root/resources
    chmod -R u+w $root/resources
    # Le .deb renvoie les polices KaTeX vers le paquet Debian fonts-katex
    # (/usr/share/fonts) : liens pendants, retirés (seul le rendu des formules
    # de l'interface web en dépend).
    find $root/resources -xtype l -delete
    # Copie de defaults.json où seul flm.prefer_system passe à true : sinon
    # Lemonade ignore le `flm` du PATH et voudrait télécharger son propre binaire
    # FLM, inutilisable sur NixOS. Le fichier amont reste intact ; la clé existe
    # aussi dans d'autres sections, d'où jq plutôt que sed.
    jq '.flm.prefer_system = true' $root/resources/defaults.json > $root/defaults-nixos.json
    install -Dm644 LICENSE $out/share/doc/lemonade-server/LICENSE
    runHook postInstall
  '';

  # FastFlowLM est mis dans le PATH de lemond : le serveur y lance `flm`
  # pour les modèles NPU, sans installation automatique en ligne.
  # LEMONADE_DEFAULTS_PATH (surchargeable) pointe sur la copie à flm.prefer_system.
  postFixup = ''
    makeWrapper $out/lib/lemonade-server/lemond $out/bin/lemond \
      --set-default LEMONADE_DEFAULTS_PATH $out/lib/lemonade-server/defaults-nixos.json \
      --prefix PATH : ${lib.makeBinPath [ fastflowlm ]}
    makeWrapper $out/lib/lemonade-server/lemonade $out/bin/lemonade \
      --prefix PATH : ${lib.makeBinPath [ fastflowlm ]}
  '';

  passthru.updateScript = [ "python3" "scripts/update.py" "lemonade-server" ];

  meta = {
    description = "Serveur Lemonade (lemond, API compatible OpenAI) et client lemonade, sans application de bureau";
    homepage = "https://github.com/lemonade-sdk/lemonade";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "lemond";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
