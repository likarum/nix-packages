# nix-packages

Recettes personnelles de likarum. Un flake, sept paquets, mises à jour proposées
par GitHub Actions. Aucun déploiement, service persistant, cache tiers ou secret
n'est ajouté par ce flake.

## Paquets

| Attribut | Origine et adaptations |
|---|---|
| `claude-desktop` | `.deb` Anthropic ; environnement FHS, correctifs Cowork ; options `browser` et `passwordStore` |
| `chatgpt-desktop` | `.deb` OpenAI ; adaptation ELF, copie depuis le store et détection libc ; options `browser` et `passwordStore` |
| `coroslink` | AppImage du projet CorosLink ; lanceur, icône, ffmpeg/yt-dlp |
| `claude-code-libsecret` | Claude Code de nixpkgs-unstable avec libsecret dans le chemin des bibliothèques |
| `sddm-theme-hexa-retro` | Thème QML maison et animation issue du thème Plymouth hexa_retro |
| `fastflowlm` | Archive portable officielle FastFlowLM (commande `flm`), avec XRT 2.25 et le greffon `amdxdna` embarqués ; **non libre** |
| `lemonade-server` | Binaires officiels `lemond` et `lemonade` (API compatible OpenAI, port 13305) ; `flm` dans leur `PATH` |

Les sorties exposées et la CI ciblent **x86_64-linux**. Les manifests Debian
conservent aussi les hashes arm64, sans prétendre valider cette architecture.
PrismLauncher, Basic Memory et Hermes ne sont pas migrés dans ce dépôt.

## Utilisation

```bash
nix build github:likarum/nix-packages#chatgpt-desktop
nix run github:likarum/nix-packages#chatgpt-desktop
```

`nix run` lance réellement l'application avec les droits de l'utilisateur.
Le premier lancement interactif doit vérifier login, keyring, fichiers et outils.
Un build vert ne valide pas ces fonctions.

Dans un flake NixOS :

```nix
inputs.maison = {
  url = "github:likarum/nix-packages";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
};
```

Ajouter `maison` aux arguments de `outputs`, puis l'overlay au module de l'hôte :

```nix
nixpkgs.overlays = [ maison.overlays.default ];
nixpkgs.config.allowUnfree = true;
```

L'overlay utilise `pkgs.unstable.claude-code` si le consommateur expose déjà cet
ensemble ; sinon il utilise le nixpkgs-unstable verrouillé ici. Les autres paquets
utilisent le nixpkgs du consommateur. La CI NixOS doit donc aussi évaluer le
résultat de l'intégration après chaque mise à jour de l'input.

Installer les paquets choisis dans `environment.systemPackages` ou dans le profil
utilisateur. Exemple adapté à une session Hyprland :

```nix
users.users.likarum.packages = [
  (pkgs.claude-desktop.override {
    browser = pkgs.brave;
    passwordStore = "gnome-libsecret";
  })
  (pkgs.chatgpt-desktop.override {
    browser = pkgs.brave;
    passwordStore = "gnome-libsecret";
  })
];
services.gnome.gnome-keyring.enable = true;
# Pour le runtime documentaire téléchargé par ChatGPT :
programs.nix-ld.enable = true;
```

Pour le thème :

```nix
services.displayManager.sddm.theme =
  "${pkgs.sddm-theme-hexa-retro}/share/sddm/themes/hexa_retro";
```

Claude Desktop/Cowork conserve ses besoins existants : accès KVM et environnement
FHS/bubblewrap. Le flake ne donne pas automatiquement de groupes à un utilisateur.

## NPU AMD XDNA 2 (`fastflowlm`, `lemonade-server`)

Pour un Ryzen AI à NPU XDNA 2 (Strix, Krackan, Gorgon). Le flake n'empaquette ni
le pilote noyau ni le firmware ; il ne déclare aucun service.

L'hôte doit fournir :

- noyau 7.0 ou plus avec le module `amdxdna` et le firmware NPU (1.1.0.0 ou plus),
  `/dev/accel/accel0` présent ;
- l'utilisateur dans les groupes `render` et `video` (accès à `/dev/accel`) ;
- une limite memlock illimitée pour cet utilisateur
  (`security.pam.loginLimits`, ou `LimitMEMLOCK=infinity` dans un service) ;
- de la place pour les modèles : `flm` les télécharge (réseau, Hugging Face) dans
  `~/.config/flm/models`, ou dans le dossier de `FLM_MODEL_PATH`.

Essai sans rien installer :

```bash
nix run github:likarum/nix-packages#fastflowlm -- validate
nix run github:likarum/nix-packages#fastflowlm -- run gemma3:1b
nix run github:likarum/nix-packages#lemonade-server -- --port 13305
```

`nix run` ... `lemond` expose l'API sur `http://127.0.0.1:13305` ; `lemonade --help`
liste les commandes du client. Le paquet `fastflowlm` est non libre : activer
`nixpkgs.config.allowUnfree = true` (ou un prédicat pour `fastflowlm`).

Le wrapper de `flm` fixe `FLM_XCLBIN_PATH`, `FLM_MODELINFO_PATH`,
`FLM_CONFIG_PATH` (paquet lui-même) et `FLM_DISABLE_UPDATE_CHECK=1`. Ces variables
restent surchargeables. `lemonade-server` ne contient ni ROCm, ni Vulkan, ni
génération d'images, ni application de bureau ; FFmpeg n'est pas fourni (entrée
vidéo/audio de `flm` non couverte). Une régression amont connue
(ROCm/FastFlowLM#655) fait échouer le chargement d'un modèle quand `--asr 1` et
`--embed 1` sont activés ensemble : n'en utiliser qu'un à la fois.

Limites : ces paquets sont construits et testés sans NPU (démarrage, aide, liste
des modèles, serveur sans modèle). `flm validate`, le chargement d'un modèle et
l'inférence ne sont validés que sur une machine équipée ; un build vert ne les
garantit pas. La mise à jour automatique (`scripts/update.py`, workflow Update)
ne les couvre pas encore.

## Mises à jour

- Tous les jours à 05:17 UTC : recherche de versions Claude Desktop, ChatGPT et
  CorosLink. Le cron GitHub est indicatif et peut être retardé.
- Le lundi : mise à jour des deux inputs nixpkgs, qui mettent aussi à jour Claude
  Code et la base du thème.
- À la demande : Actions → Update → Run workflow, avec sélection d'un paquet ou
  de tous les paquets (`all` inclut les inputs).
- Une PR par cible, réutilisée tant qu'elle est ouverte. Aucun auto-merge.
- Les versions et hashes sont les seuls changements automatiques des recettes.
  Un correctif qui ne s'applique plus doit être repris manuellement.
- Les builds et tests sont exécutés avant ouverture de la PR. Un échec conserve
  `main` intact et apparaît dans Actions ; aucun pin cassé n'est fusionné.

Commandes locales :

```bash
nix develop
python3 scripts/update.py chatgpt-desktop --verify
python3 scripts/update.py claude-desktop --check
python3 scripts/update.py coroslink
nix flake update nixpkgs nixpkgs-unstable
nix flake check --print-build-logs
```

Le token intégré `GITHUB_TOKEN` suffit : activer « Allow GitHub Actions to create
and approve pull requests » dans Settings → Actions → General. Il n'y a aucun
secret PAT à créer. Les workflows de PR créées par ce token peuvent nécessiter
une approbation GitHub ; les tests du workflow Update sont donc exécutés avant
création de la PR, sans dépendre du déclenchement d'un second workflow.
Les Actions sont figées à des commits, checkout ne persiste pas les credentials,
et seul le job Update a les droits d'écriture nécessaires aux PR.

Dans le dépôt NixOS, une fusion ici ne change rien au pin consommé :

```bash
nix flake update maison
nix build .#nixosConfigurations.archon.config.system.build.toplevel
# Sur la machine cible, après revue :
sudo nixos-rebuild test --flake .#archon
sudo nixos-rebuild switch --flake .#archon
```

Pour revenir à une recette précédente, restaurer le `flake.lock` antérieur du
consommateur et reconstruire. Cela ne restaure pas les données dans le home.

## Limites de confiance

- OpenAI : l'updater vérifie InRelease avec la clé locale et son empreinte fixée,
  puis la taille et le SHA256 de l'index Packages. Nix vérifie le `.deb` au build.
  La clé initiale provient du packaging tiers documenté dans `PROVENANCE.md` :
  sa racine de confiance reste le bootstrap TLS initial, pas une preuve indépendante.
- Anthropic : index officiel HTTPS, SHA256 fourni par l'index et vérifié par Nix.
  Aucune vérification PGP n'est revendiquée pour cette source.
- CorosLink : téléchargement de l'AppImage officielle du projet tiers et calcul
  du SHA256 ; comparaison au digest GitHub si présent. Aucun build depuis les
  sources ni signature éditeur n'est revendiqué. Le lanceur conserve les flags
  existants, dont `--no-sandbox` : extraire la recette ne renforce pas son isolation.
- Les downgrades et les changements de hash/URL d'une version existante sont
  refusés par l'updater. Les mises à jour ne relisent pas automatiquement les
  modifications du code propriétaire embarqué.
- ChatGPT télécharge un runtime documentaire dans `~/.cache/codex-runtimes`, hors
  du store et du verrouillage Nix. Il partage `~/.codex` avec Codex CLI.
- NixOS n'est pas officiellement supporté par ChatGPT Linux. Les deux correctifs
  JavaScript sont locaux, attribués et testés ; ils n'ont pas pour but de modifier
  les politiques d'autorisation de l'agent.
- Aucun cache binaire de ce dépôt n'est publié : cela évite également de
  redistribuer les applications propriétaires.
- FastFlowLM et Lemonade : archives et `.deb` des releases GitHub officielles,
  hash SHA256 fixé et vérifié par Nix ; aucune signature éditeur n'est
  revendiquée. `autoPatchelf` modifie les binaires dans le store du consommateur.

## Licences et provenance

Le code original de packaging est MIT, sauf le thème QML GPL-3.0 indiqué dans
ses métadonnées. Les parties reprises conservent leurs licences et attributions
(`licenses/`, `PROVENANCE.md`). Les applications et ressources empaquetées restent
sous leurs propres licences ; la licence de ce dépôt ne les relicencie pas.
