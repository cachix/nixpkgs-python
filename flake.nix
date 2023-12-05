{
  description = "All Python versions packages in Nix.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  nixConfig = {
    substituters = "https://cache.nixos.org https://nixpkgs-python.cachix.org";
    extra-trusted-public-keys = "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=";
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
        , callPackage
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
          overrideLDConfigPatch = path: pkg: pkg.override {
            noldconfigPatch = path;
          };
          replacePatch = name: patch: pkg: pkg.overrideAttrs (old: {
            patches = (lib.filter (elem: if builtins.isNull elem then true else !lib.hasSuffix name elem) old.patches) ++ [ patch ];
          });
          filterOutPatch = name: pkg: replacePatch name null pkg;
          overrides = [
            # py2
            { condition = version: versionInBetween version "2.7.3" "2.6";
              # patch not available
              override = pkg: filterOutPatch "deterministic-build.patch" (filterOutPatch "no-win64-workaround.patch" pkg);
            }
            { condition = version: versionInBetween version "2.7.4" "2.6";
              # patch not available
              override = filterOutPatch "atomic_pyc.patch";
            }
            { condition = version: versionInBetween version "2.7.13" "2.6";
              override = pkg: filterOutPatch "find_library-gcc10.patch" (filterOutPatch "profile-task.patch" pkg);
            }
            # patch not available before 2.7.11
            { condition = version: versionInBetween version "2.7.11" "2.6";
              override = filterOutPatch "no-ldconfig.patch";
            }
            { condition = version: versionInBetween version "2.7.12" "2.7.11";
              override = replacePatch "no-ldconfig.patch" ./patches/2.7.10-no-ldconfig.patch;
            }
            { condition = version: versionInBetween version "2.7.13" "2.7.12";
              override = replacePatch "no-ldconfig.patch" ./patches/2.7.11-no-ldconfig.patch;
            }
            { condition = version: versionInBetween version "2.7.17" "2.7.6";
              override = replacePatch "python-2.7-distutils-C++.patch" ./patches/2.7.17-distutils-C++.patch;
            }
            # py3
            { condition = version: versionInBetween version "3.8.7" "3.8";
              override = overrideLDConfigPatch ./patches/3.8.6-no-ldconfig.patch;
            }
            { condition = version: versionInBetween version "3.7.10" "3.7";
              override = overrideLDConfigPatch ./patches/3.7.9-no-ldconfig.patch;
            }
            { condition = version: versionInBetween version "3.7.3" "3.7";
              override = filterOutPatch "fix-finding-headers-when-cross-compiling.patch";
            }
            { condition = version: versionInBetween version "3.7.3" "3.7.1";
              override = replacePatch "python-3.x-distutils-C++.patch" (pkgs.fetchpatch {
                url = "https://bugs.python.org/file48016/python-3.x-distutils-C++.patch";
                sha256 = "1h18lnpx539h5lfxyk379dxwr8m2raigcjixkf133l4xy3f4bzi2";
              });
            } 
            { condition = version: versionInBetween version "3.7.4" "3.7.3";
              override = replacePatch "python-3.x-distutils-C++.patch" ./patches/python-3.7.3-distutils-C++.patch;
            }
            {
              condition = version: versionInBetween version "3.7.2" "3.7" || versionInBetween version "3.6.8" "3.6.6";
              override = replacePatch "python-3.x-distutils-C++.patch" (pkgs.fetchpatch {
                url = "https://bugs.python.org/file47669/python-3.8-distutils-C++.patch";
                sha256 = "0s801d7ww9yrk6ys053jvdhl0wicbznx08idy36f1nrrxsghb3ii";
              });
            }
            { condition = version: versionInBetween version "3.5.3" "3.5";
              # no existing patch available
              override = overrideLDConfigPatch null;
            }
            { condition = version: versionInBetween version "3.6.6" "3.4";
              override = replacePatch "python-3.x-distutils-C++.patch" (pkgs.fetchpatch {
                url = "https://bugs.python.org/file47046/python-3.x-distutils-C++.patch";
                sha256 = "0dgdn9k2kmw4wh90vdnjcrnn97ylxgx7mbn9l87fwz6j501jqvk8";
                extraPrefix = "";
              });
            }
            # no C++ patch for 3.3
            { condition = version: versionInBetween version "3.4" "3.0";
              override = filterOutPatch "python-3.x-distutils-C++.patch";
            }
            # fix darwin compilation
            { condition = version: versionInBetween version "3.8.4" "3.8" || versionInBetween version "3.7.8" "3.0";
              override = pkg: pkg.overrideAttrs (old: {
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
            # fill in the missing pc file
            { condition = version: versionInBetween version "3.5.2" "3.0" && pkgs.stdenv.isLinux;
              override = pkg: pkg.overrideAttrs (old: {
                postInstall = '' 
                  ln -s "$out/lib/pkgconfig/python-${pkg.passthru.sourceVersion.major}.${pkg.passthru.sourceVersion.minor}.pc" "$out/lib/pkgconfig/python3.pc"
                ''+ old.postInstall;
              });
            }
          ];
        in (self.lib.applyOverrides overrides (pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/cpython/${infix}default.nix" ({ 
          inherit sourceVersion;
          inherit (pkgs.darwin) configd;
          hash = null;
          self = callPackage ./self.nix { inherit version; };
          passthruFun = pkgs.callPackage "${pkgs.path}/pkgs/development/interpreters/python/passthrufun.nix" { };
        } // lib.optionalAttrs (sourceVersion.major == "3") {
          noldconfigPatch = ./patches + "/${sourceVersion.major}.${sourceVersion.minor}-no-ldconfig.patch";
        }))).overrideAttrs (old: {
          src = pkgs.fetchurl {
            inherit url;
            sha256 = hash;
          };
          meta = old.meta // {
            knownVulnerabilities = [];
          };
        });

    lib.versions = builtins.fromJSON (builtins.readFile ./versions.json);

    checks = forAllSystems (system:
      let
        callPackage = lib.callPackageWith (pkgs // { nixpkgs-python = packages; });
        pkgs = nixpkgs.legacyPackages.${system};
        getRelease = callPackage: version: source: self.lib.mkPython { 
          inherit pkgs version callPackage; 
          inherit (source) hash url;
        };
        getLatest = callPackage: version: latest:
          getRelease callPackage latest self.lib.versions.releases.${latest};
        packages = pkgs.lib.mapAttrs (getRelease callPackage) self.lib.versions.releases 
          // pkgs.lib.mapAttrs (getLatest callPackage) self.lib.versions.latest;
      in packages
    );

    packages = self.checks;
  };
}
