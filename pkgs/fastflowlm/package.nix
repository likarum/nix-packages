{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, curl
, libuuid
, libedit
, gcc
}:
let
  sources = lib.importJSON ./sources.json;
  src = fetchurl { inherit (sources.sources.x86_64-linux) url hash; };
  # Texte du fichier LICENSE_BINARY.txt de l'archive : noyaux .xclbin et
  # bibliothèques de moteurs NPU, gratuits mais fermés, redistribuables tels quels.
  npuBinaryLicense = {
    shortName = "fastflowlm-npu-binary";
    fullName = "FastFlowLM NPU Binary License (AMD)";
    url = "https://github.com/ROCm/FastFlowLM/blob/main/LICENSE_BINARY.txt";
    free = false;
    redistributable = true;
  };
in
stdenv.mkDerivation {
  pname = "fastflowlm";
  inherit (sources) version;
  inherit src;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [
    curl
    libuuid
    libedit
    gcc.cc.lib # libstdc++, libgomp, libgcc_s
  ];

  # L'archive « portable » amont embarque déjà XRT 2.25 et le greffon xdna
  # (libxrt_driver_xdna) à côté de flm-real : rien à compiler.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    root=$out/lib/fastflowlm
    mkdir -p $root/lib $out/share/flm $out/share/doc/fastflowlm $out/bin

    install -Dm755 flm-real $root/flm-real
    cp -a lib/. $root/lib/

    # XRT >= 2.25 déduit sa racine de l'emplacement chargé de libxrt_coreutil
    # (dladdr), puis cherche le greffon dans <racine>/lib/x86_64-linux-gnu.
    # L'amont recrée ce miroir au lancement ; le store étant en lecture seule,
    # les bibliothèques XRT y sont placées une fois pour toutes.
    mkdir -p $root/lib/x86_64-linux-gnu
    mv $root/lib/libxrt* $root/lib/x86_64-linux-gnu/
    # Émulateurs et HIP : inutiles pour le NPU matériel, ils tirent protobuf.
    rm -f $root/lib/x86_64-linux-gnu/libxrt_{hwemu,swemu,hip}.so*

    cp -a xclbins $out/share/flm/xclbins
    install -Dm644 model_list.json model_info.json -t $out/share/flm
    install -Dm644 LICENSE_BINARY.txt LICENSE_RUNTIME.txt THIRD_PARTY_NOTICES.txt \
      -t $out/share/doc/fastflowlm

    runHook postInstall
  '';

  # Les moteurs NPU (lib*_npu.so) sont des dépendances NEEDED de flm-real :
  # autoPatchelf les résout dans $root/lib et le miroir XRT ci-dessus.
  preFixup = ''
    addAutoPatchelfSearchPath $out/lib/fastflowlm/lib
    addAutoPatchelfSearchPath $out/lib/fastflowlm/lib/x86_64-linux-gnu
  '';

  postFixup = ''
    makeWrapper $out/lib/fastflowlm/flm-real $out/bin/flm \
      --set XILINX_XRT $out/lib/fastflowlm \
      --set-default FLM_XCLBIN_PATH $out/share/flm/xclbins \
      --set-default FLM_MODELINFO_PATH $out/share/flm/model_info.json \
      --set-default FLM_CONFIG_PATH $out/share/flm/model_list.json \
      --set-default FLM_DISABLE_UPDATE_CHECK 1
  '';

  passthru.updateScript = [ "python3" "scripts/update.py" "fastflowlm" ];

  meta = {
    description = "Runtime LLM FastFlowLM pour NPU AMD XDNA 2 (commande flm), avec XRT embarqué";
    longDescription = ''
      Réemballage de l'archive portable officielle. Source amont sous MIT
      (LICENSE_RUNTIME.txt) ; noyaux .xclbin et moteurs NPU sous licence binaire
      AMD (LICENSE_BINARY.txt), donc paquet non libre. Le pilote noyau amdxdna
      et le firmware NPU doivent être fournis par l'hôte.
    '';
    homepage = "https://github.com/ROCm/FastFlowLM";
    license = [ lib.licenses.mit npuBinaryLicense ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "flm";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
