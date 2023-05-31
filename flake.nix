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
    lib.applyOverrides = overrides: pkg:
      let
        matching = builtins.filter ({ condition, ... }: condition pkg.version) overrides;
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
          overrides = [
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
          { condition = version: versionInBetween version "3.7.3" "3.7";
            override = pkg: pkg.overrideAttrs (old: {
              patches = lib.filter (elem: if builtins.isNull elem then true else !lib.hasSuffix "fix-finding-headers-when-cross-compiling.patch" elem) old.patches;
            });
          }
          { condition = version: versionInBetween version "3.5.3" "3.5";
            override = pkg: pkg.override {
              # no existing patch available
              noldconfigPatch = null;
            };
          }
          { condition = version: versionInBetween version "3.6.8" "3.4";
            override = pkg: pkg.overrideAttrs (old: {
              patches = (lib.filter (elem: if builtins.isNull elem then true else  !lib.hasSuffix "python-3.x-distutils-C++.patch" elem) old.patches)
                 ++ [ (pkgs.fetchpatch {
                        url = "https://bugs.python.org/file47046/python-3.x-distutils-C++.patch";
                        sha256 = "0dgdn9k2kmw4wh90vdnjcrnn97ylxgx7mbn9l87fwz6j501jqvk8";
                        extraPrefix = "";
                    })];
            });
          }
          # no C++ patch for 3.3
          { condition = version: versionInBetween version "3.4" "3.0";
            override = pkg: pkg.overrideAttrs (old: {
              patches = (lib.filter (elem: if builtins.isNull elem then true else  !lib.hasSuffix "python-3.x-distutils-C++.patch" elem) old.patches);
            });
          }
          # fix darwin compilation
          { condition = version: versionInBetween version "3.8.4" "3.8" || versionInBetween version "3.7.8" "3.7";
            override = pkg: pkg.overrideAttrs (old: {
              # no existing patch available
              patches = old.patches ++ [(pkgs.fetchpatch {
                url = "https://github.com/python/cpython/commit/8ea6353.patch";
                sha256 = "xXRDwtMMhb66J4Lis0rtTNxARgPqLAqR2y3YtkJOt2g=";
              })];
            });

          }
          { condition = version: versionInBetween version "3.4" "3.0";
            override = pkg: (pkg.override {
              # no existing patch available
              noldconfigPatch = null;
              # otherwise it segfaults
              stdenv = 
                if pkgs.stdenv.isLinux
                then pkgs.overrideCC pkgs.stdenv pkgs.gcc8
                else pkgs.stdenv;
            });
          }
          { condition = version: versionInBetween version "3.5.2" "3.0" && pkgs.stdenv.isLinux;
            override = pkg: pkg.overrideAttrs (old: {
              # fill in the missing pc file
              postInstall = '' 
                ln -s "$out/lib/pkgconfig/python-${pkg.passthru.sourceVersion.major}.${pkg.passthru.sourceVersion.minor}.pc" "$out/lib/pkgconfig/python3.pc"
              ''+ old.postInstall;
            });
          }
        ];
        in self.lib.applyOverrides overrides (pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/cpython/${infix}default.nix" { 
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
