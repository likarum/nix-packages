{
  description = "Paquets personnels de likarum : recettes relues et mises à jour par PR";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      # First supported target: the architecture of the consuming NixOS hosts.
      # Debian pins for arm64 are kept too, but no untested arm64 outputs advertised.
      system = "x86_64-linux";
      unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };
      overlay = final: prev: {
        claude-desktop = final.callPackage ./pkgs/claude-desktop/package.nix { };
        chatgpt-desktop = final.callPackage ./pkgs/chatgpt-desktop/package.nix { };
        coroslink = final.callPackage ./pkgs/coroslink/package.nix { };
        claude-code-libsecret = final.callPackage ./pkgs/claude-code-libsecret/package.nix {
          claude-code = (prev.unstable or unstable).claude-code;
        };
        sddm-theme-hexa-retro = final.callPackage ./pkgs/sddm-theme-hexa-retro/package.nix { };
      };
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ overlay ];
      };
    in {
      overlays.default = overlay;
      packages.${system} = {
        inherit (pkgs) claude-desktop chatgpt-desktop coroslink
          claude-code-libsecret sddm-theme-hexa-retro;
      };
      apps.${system} = builtins.listToAttrs (map (name: {
        inherit name;
        value = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${system}.${name};
          meta.description = "Launch ${name}";
        };
      }) [ "claude-desktop" "chatgpt-desktop" "coroslink" "claude-code-libsecret" ]);
      checks.${system} = import ./tests/checks.nix { inherit pkgs; };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ python3 curl gnupg dpkg jq git shellcheck actionlint nixfmt ];
      };
      formatter.${system} = pkgs.nixfmt;
    };
}
