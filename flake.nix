{
  description = "All Python versions packages in Nix.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  nixConfig = {
    substituters = "https://cache.nixos.org https://nixpkgs-python.cachix.org";
    extra-trusted-public-keys = "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=";
  };

  outputs = { self, nixpkgs, ... }:
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
        , packages
        }:
        let
          versionList = builtins.splitVersion version;
          versionSuffixList = builtins.concatLists [[""] (lib.drop 3 versionList)];
          sourceVersion = {
            major = builtins.elemAt versionList 0;
            minor = builtins.elemAt versionList 1;
            patch = builtins.elemAt versionList 2;
            suffix = builtins.concatStringsSep "." versionSuffixList;
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
            { condition = version: versionInBetween version "3.7" "3.3";
              # patch not available
              override = filterOutPatch "loongarch-support.patch";
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
            # this patch reverts an ActiveState change that was introduced in 2.7.18.8
            { condition = version: versionInBetween version "2.7.18.8" "2.7";
              override = pkg: filterOutPatch "20ea5b46aaf1e7bdf9d6905ba8bece2cc73b05b0.patch" pkg;
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
            # Fix ensurepip for 3.6: https://bugs.python.org/issue45700
            { condition = version: versionInBetween version "3.6.15" "3.6";
              override = pkg: pkg.overrideAttrs (old: {
                patches = old.patches ++ [(pkgs.fetchpatch {
                  url = "https://github.com/python/cpython/commit/8766cb74e186d3820db0a855.patch";
                  sha256 = "IzAp3M6hpSNcbVRttzvXNDyAVK7vLesKZDEDkdYbuww=";
                })
                (pkgs.fetchpatch {
                  url = "https://github.com/python/cpython/commit/f0be4bbb9b3cee876249c23f.patch";
                  sha256 = "FUF7ZkkatS4ON4++pR9XJQFQLW1kKSVzSs8NAS19bDY=";
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
            # compatibility with substitutions done by the nixpkgs derivation
            { condition = version: versionInBetween version "3.7" "3.0";
              override = pkg: pkg.overrideAttrs  (old: {
                prePatch = ''
                  substituteInPlace Lib/subprocess.py --replace '"/bin/sh"' "'/bin/sh'"
                '' + old.prePatch;
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
          callPackage = pkgs.newScope {
            inherit python;
            pkgsBuildHost = pkgs.pkgsBuildHost // {
              "python${sourceVersion.major}${sourceVersion.minor}" = python;
            };
          };
          python = (self.lib.applyOverrides overrides (callPackage "${pkgs.path}/pkgs/development/interpreters/python/cpython/${infix}default.nix" ({
            inherit sourceVersion;
            inherit (pkgs.darwin) configd;
            hash = null;
            self = packages.${version};
            passthruFun = callPackage "${pkgs.path}/pkgs/development/interpreters/python/passthrufun.nix" { };
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
        in python;

    lib.versions = builtins.fromJSON (builtins.readFile ./versions.json);

    packages = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        getRelease = version: source: self.lib.mkPython {
          inherit pkgs version packages;
          inherit (source) hash url;
        };
        getLatest = version: latest:
          getRelease latest self.lib.versions.releases.${latest};
        packages = pkgs.lib.mapAttrs getRelease self.lib.versions.releases
          // pkgs.lib.mapAttrs getLatest self.lib.versions.latest;
      in packages
    );

    checks = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.lib.concatMapAttrs (version: python: {
          ${version} = python;
        } // lib.optionalAttrs (versionInBetween version "3" "2.7.18") {
          ${version + "-ssl"} = pkgs.runCommand "${version}-test-ssl" { } ''
            set -x

            mkdir $out
            ${python}/bin/python -c 'import ssl; print(ssl.OPENSSL_VERSION)' | tee $out/openssl-version
          '';
        } // lib.optionalAttrs (versionInBetween version "3.12" "3.6") {
          ${version + "-ensurepip"} = pkgs.runCommand "${version}-test-ensurepip" { } ''
            set -x

            mkdir $out
            ${python}/bin/python -m ensurepip --help | tee $out/ensurepip-help
          '';
        }) self.packages.${system});
  };
}
