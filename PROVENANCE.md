# Provenance des recettes

- `pkgs/claude-desktop/package.nix` : extrait de la configuration NixOS de likarum,
  elle-même basée sur https://github.com/NixOS/nixpkgs/pull/537215. Les correctifs
  locaux Cowork/FHS, navigateur et keyring sont conservés. Licence du packaging
  nixpkgs : `licenses/nixpkgs-MIT.txt`. Les auteurs indiqués par la recette sont
  conservés. Les binaires proviennent de `downloads.claude.ai`.
- `pkgs/chatgpt-desktop/package.nix` et `nix/*.js`, `nix/patch-asar.cjs` : adaptés
  de https://github.com/danielbodart/chatgpt-desktop au commit
  `0760c41619de6572fb921de6561357496afe94db` (MIT, Dan Bodart ; texte conservé dans
  `licenses/chatgpt-packaging-MIT.txt`). Adaptations locales : options navigateur
  et keyring, updater commun, aucune configuration du cache Cachix tiers.
- `pkgs/chatgpt-desktop/openai-archive-keyring.asc` : clé publique reprise du même
  commit. Empreinte `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4` (« Codex Linux
  Repository »). L'amont décrit son extraction du postinst d'un `.deb` OpenAI
  téléchargé par HTTPS. Notre updater n'exécute jamais ce postinst, ni aucun
  script téléchargé, et refuse toute rotation automatique de clé.
- Les sources ChatGPT sont vérifiées contre l'index signé officiel à l'intégration.
  Source produit : https://learn.chatgpt.com/docs/linux/linux-app.
- `pkgs/coroslink/` : recette extraite de `common/coroslink.nix`, configuration
  personnelle de likarum. Binaire : https://github.com/JunAkerBuilds/CorosLink.
- `pkgs/claude-code-libsecret/` : wrapper extrait de `common/users.nix`, sans
  modifier le binaire Claude Code fourni par nixpkgs-unstable.
- `pkgs/sddm-theme-hexa-retro/` : recette et QML extraits de
  `common/desktop/sddm-hexa-retro*`, auteur likarum, GPL-3.0 selon metadata.desktop.
  Les images proviennent du paquet nixpkgs `adi1090x-plymouth-themes` et ne sont
  pas copiées dans ce dépôt. Les réglages SDDM de l'hôte restent dans NixOS.
- `pkgs/fastflowlm/` : recette originale, MIT. Binaire : archive portable
  `fastflowlm_1.0.12_linux.tar.gz` de https://github.com/ROCm/FastFlowLM (release
  v1.0.12, marquée « Latest » au 2026-11-11). Choix : l'archive embarque déjà XRT
  2.25 et le greffon `libxrt_driver_xdna`, ce qui évite de compiler XRT
  (Xilinx/XRT, xdna-driver, sous-modules, long à construire sur la CI) ; aucun paquet `xrt` séparé n'est
  donc fourni. Licences : source MIT (`LICENSE_RUNTIME.txt`) ; noyaux `.xclbin` et
  moteurs NPU sous `LICENSE_BINARY.txt` d'AMD (usage et redistribution gratuits
  si non modifiés, texte inclus par le paquet dans `share/doc/fastflowlm`) ; le
  `TERMS.md` mentionné par d'anciennes versions n'existe plus dans l'amont.
  Déclarée `unfree` dans `meta.license`. La mise en place du miroir
  `lib/x86_64-linux-gnu` (racine XRT via `dladdr`) reprend la logique du script
  `flm` de l'archive, appliquée à la construction. Version : la 1.0.12 est la
  dernière stable ; la régression ROCm/FastFlowLM#655 (`--asr` + `--embed`
  simultanés) est ouverte et non propre à une version.
- `pkgs/lemonade-server/` : recette originale, MIT. Binaires `lemond` et `lemonade` :
  archive `lemonade-embeddable-2026.44.1-ubuntu-x64.tar.gz` de
  https://github.com/lemonade-sdk/lemonade (Apache-2.0, `LICENSE` conservé).
  Ressources (interface web, schémas) : données du `.deb` Debian 13 de la même
  release, ses binaires ne sont pas utilisés. Choix de la 2026.44.1 : la 2026.45.3
  exige glibc 2.43, absente de NixOS 26.05 (glibc 2.42) ; les binaires du `.deb`
  exigeraient des bibliothèques Debian absentes de nixpkgs (cpp-httplib 0.41,
  libwebsockets 19). Adaptation locale : copie de `defaults.json` avec seul
  `flm.prefer_system = true` (jq), désignée par `LEMONADE_DEFAULTS_PATH` dans le
  wrapper de `lemond`, pour que Lemonade utilise le `flm` du paquet au lieu de
  télécharger son propre FLM.
- Étudié sans reprise de code : https://github.com/noamsto/nix-amd-ai (MIT,
  commit `e11eddc66283c8b99a29b2ecfc719d6e7e50f791`), qui compile XRT, le greffon,
  FastFlowLM et Lemonade depuis les sources. Aucune recette n'en a été copiée,
  donc aucun texte de licence supplémentaire n'est joint.

Aucune configuration réseau, clé privée, donnée utilisateur ou secret du dépôt
NixOS n'est inclus dans ce dépôt de paquets.
