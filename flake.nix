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
      lib = nixpkgs.lib;
      versionInBetween = version: lower: upper:
        lib.versionOlder version lower && lib.versionAtLeast version upper;
    in {
    lib.overrides = [
      { condition = version: versionInBetween version "3.8.7" "3.8";
        override = pkg: pkg.override {
          noldconfigPatch = ./patches/3.8.6-no-ldconfig.patch;
        };
      }
      { condition = version: versionInBetween version "3.7.10" "3.7";
        override = pkg: pkg.override {
          noldconfigPatch = ./patches/3.7.9-no-ldconfig.patch;
        };
      }
      { condition = version: lib.versionOlder version "3.3.100";
        override = pkg: pkg.override {
          noldconfigPatch = null;
        };
      }
    ];
    lib.applyOverrides = pkg:
      let
        matching = builtins.filter ({ condition, ... }: condition pkg.version) self.lib.overrides;
        apply = pkg: { override, ... }: override pkg;
      in lib.foldl apply pkg matching;
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
          infix = if sourceVersion.major == "2" then "2.7/" else "";
        in self.lib.applyOverrides (pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/cpython/${infix}default.nix" { 
          inherit sourceVersion url;
          inherit (pkgs.darwin) configd;
          passthruFun = pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/passthrufun.nix" { };
          hash = "sha256-${hash}";
          noldconfigPatch = ./patches + "/${sourceVersion.major}.${sourceVersion.minor}-no-ldconfig.patch";
        });

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
