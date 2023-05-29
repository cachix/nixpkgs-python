{
  inputs = {
    nixpkgs.url = "github:domenkozar/nixpkgs/cpython-moduralize";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  nixConfig = {
    substituters = "https://cache.nixos.org"; # https://python.cachix.org";
    extra-trusted-public-keys = "python.cachix.org-1:66x3z4afDDpQOUXdGcmFXwj3xJwQyRevOx0EdwR076Y=";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: 
    let 
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) systems);
    in rec {
    lib.mkPython =
        { pkgs
        , version
        , hash
        , url
        }:
        let
          versionList = builtins.splitVersion version;
          sourceVersion = {
            major = builtins.elemAt versionList 0;
            minor = builtins.elemAt versionList 1;
            patch = builtins.elemAt versionList 2;
            suffix = "";
          };
        in pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/cpython/default.nix" { 
          inherit sourceVersion url;
          inherit (pkgs.darwin) configd;
          passthruFun = pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/passthrufun.nix" { };
          hash = "sha256-${hash}";
          noldconfigPatch = ./patches + "/${sourceVersion.major}.${sourceVersion.minor}-no-ldconfig.patch";
        };

    lib.versions = builtins.fromJSON (builtins.readFile ./versions.json);

    checks = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        getRelease = version: source: self.lib.mkPython { 
          inherit pkgs version; 
          inherit (source) hash url;
        };
        getLatest = version: latest:
          getRelease latest self.lib.versions.releases.${latest};
      in pkgs.lib.mapAttrs getRelease self.lib.versions.releases 
      // pkgs.lib.mapAttrs getLatest self.lib.versions.latest
    );

    packages = self.checks;
  };
}
