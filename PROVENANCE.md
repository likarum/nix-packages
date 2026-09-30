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

Aucune configuration réseau, clé privée, donnée utilisateur ou secret du dépôt
NixOS n'est inclus dans ce dépôt de paquets.
