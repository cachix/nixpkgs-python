{
  description = "All Python versions packages in Nix.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  nixConfig = {
    extra-substituters = "https://nixpkgs-python.cachix.org";
    extra-trusted-public-keys = "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "i686-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = f name;
          }) systems
        );
      lib = nixpkgs.lib;
      versionInBetween =
        version: upper: lower:
        lib.versionAtLeast version lower && lib.versionOlder version upper;

      # Select the correct no-ldconfig patch variant for a Python 3.x version
      selectNoLdconfigPatch =
        version: patchDir:
        if versionInBetween version "3.4" "3.0" then
          ./patches/shared/no-op.patch
        else if versionInBetween version "3.5.3" "3.5" then
          ./patches/shared/no-op.patch
        else if versionInBetween version "3.7.10" "3.7" then
          patchDir + "/no-ldconfig-pre-3.7.10.patch"
        else if versionInBetween version "3.8.7" "3.8" then
          patchDir + "/no-ldconfig-pre-3.8.7.patch"
        else
          patchDir + "/no-ldconfig.patch";

      # Select the correct no-ldconfig patch variant for Python 2.x
      select2xNoLdconfigPatch =
        version: patchDir:
        if versionInBetween version "2.7.12" "2.7.11" then
          patchDir + "/no-ldconfig-2.7.10.patch"
        else if versionInBetween version "2.7.13" "2.7.12" then
          patchDir + "/no-ldconfig-2.7.11.patch"
        else if versionInBetween version "2.7.14" "2.7.13" then
          patchDir + "/no-ldconfig-2.7.12.patch"
        else
          patchDir + "/no-ldconfig.patch";

      # Select the correct distutils C++ patch variant for a Python 3.x version (Darwin-only)
      selectDistutilsCxxPatch =
        version: patchDir:
        if lib.versionAtLeast version "3.11" then
          ./patches/3.11/distutils-C++.patch
        else if lib.versionAtLeast version "3.7.3" then
          patchDir + "/distutils-C++.patch"
        else if lib.versionAtLeast version "3.7" then
          ./patches/3.7/distutils-C++-pre-3.7.3.patch
        else if lib.versionAtLeast version "3.6.6" then
          ./patches/3.6/distutils-C++-post-3.6.5.patch
        else
          patchDir + "/distutils-C++.patch";

      # Compute the complete patch list for a Python 3.x version
      patches3For =
        {
          version,
          patchDir,
          stdenv,
        }:
        let
          atLeast = lib.versionAtLeast version;
          older = lib.versionOlder version;
          hasDistutilsCxxPatch = !(stdenv.cc.isGNU or false);
          isCross = stdenv.hostPlatform != stdenv.buildPlatform;
        in
        # no-ldconfig (NixOS-specific)
        [ (selectNoLdconfigPatch version patchDir) ]
        # virtualenv-permissions (NixOS-specific)
        ++ lib.optional (atLeast "3.3") (
          if atLeast "3.13" then
            ./patches/shared/virtualenv-permissions-3.13.patch
          else
            ./patches/shared/virtualenv-permissions.patch
        )
        # mimetypes (NixOS-specific path substitution)
        ++ [ ./patches/shared/mimetypes.patch ]
        # distutils C++ — Darwin/Clang only, < 3.12 (distutils removed in 3.12)
        ++ lib.optional (hasDistutilsCxxPatch && atLeast "3.4" && older "3.12") (
          selectDistutilsCxxPatch version patchDir
        )
        # Cross-compilation: LDSHARED uses $CC instead of gcc (>= 3.7 && < 3.12)
        ++ lib.optional (atLeast "3.7" && older "3.12") ./patches/shared/LDSHARED-posix.patch
        # Cross-compilation: use sysconfigdata to find headers (>= 3.7.3 && < 3.12)
        ++ lib.optional (atLeast "3.7.3" && older "3.12")
          ./patches/shared/fix-finding-headers-when-cross-compiling.patch
        # LoongArch architecture support (>= 3.7 && < 3.12, doesn't apply to older versions)
        ++ lib.optional (atLeast "3.7" && older "3.12") ./patches/shared/loongarch-support.patch
        # Platform triplet detection fix (>= 3.11 && < 3.13)
        ++ lib.optional (atLeast "3.11" && older "3.13") ./patches/shared/platform-triplet-detection.patch
        # FreeBSD cross-compilation support
        ++ lib.optional (isCross && stdenv.hostPlatform.isFreeBSD) ./patches/shared/freebsd-cross.patch
        # Darwin compilation fix (< 3.7.8 or 3.8.0-3.8.3)
        ++ lib.optional (older "3.7.8" || versionInBetween version "3.8.4" "3.8")
          ./patches/shared/fix-darwin-compilation.patch
        # 3.5 compilation fixes
        ++ lib.optionals (versionInBetween version "3.5.2" "3.5") [
          (patchDir + "/pythreadstate-uncheckedget.patch")
          (patchDir + "/incompatible-types-atomic-pointers.patch")
        ]
        ++ lib.optionals (versionInBetween version "3.5.3" "3.5") (
          (lib.optional (version == "3.5.0") (patchDir + "/os-random-prepatch.patch"))
          ++ [ (patchDir + "/get-entropy-macos.patch") ]
        )
        # ensurepip fix for 3.6 < 3.6.15
        ++ lib.optionals (versionInBetween version "3.6.15" "3.6") [
          ./patches/3.6/ensurepip-1.patch
          ./patches/3.6/ensurepip-2.patch
        ];

      # Compute the complete patch list for a Python 2.x version
      patches2For =
        {
          version,
          patchDir,
          stdenv,
        }:
        let
          atLeast = lib.versionAtLeast version;
          older = lib.versionOlder version;
          hasDistutilsCxxPatch = !(stdenv.cc.isGNU or false);
          isDarwin = stdenv.hostPlatform.isDarwin;
          isLinux = stdenv.hostPlatform.isLinux;
          isCross = stdenv.hostPlatform != stdenv.buildPlatform;
        in
        # NixOS-specific: library/include path handling
        [ (patchDir + "/search-path.patch") ]
        # NixOS-specific: mtime=1 handling for Nix store
        ++ [ (patchDir + "/nix-store-mtime.patch") ]
        # deterministic builds (patch available >= 2.7.3)
        ++ lib.optional (atLeast "2.7.3") (patchDir + "/deterministic-build.patch")
        # Bug fix: re match index
        ++ [ (patchDir + "/re_match_index.patch") ]
        # Atomic pyc writing (patch available >= 2.7.4)
        ++ lib.optional (atLeast "2.7.4") (patchDir + "/atomic_pyc.patch")
        # PGO profile task list (patch available >= 2.7.13)
        ++ lib.optional (atLeast "2.7.13") (patchDir + "/profile-task.patch")
        # Win64 workaround fix (patch available >= 2.7.3)
        ++ lib.optional (atLeast "2.7.3") (patchDir + "/no-win64-workaround.patch")
        # ActiveState fork compat: revert their openssl change (>= 2.7.18.8)
        ++ lib.optional (atLeast "2.7.18.8") (patchDir + "/20ea5b46-openssl-revert.patch")
        # DARWIN ONLY: NixOS-specific tcl-tk path fix
        ++ lib.optional isDarwin (patchDir + "/use-correct-tcl-tk-on-darwin.patch")
        # LINUX ONLY: NixOS-specific no-ldconfig
        ++ lib.optional (isLinux && atLeast "2.7.11") (select2xNoLdconfigPatch version patchDir)
        # LINUX ONLY: find_library gcc10 fix (patch available >= 2.7.13)
        ++ lib.optional (isLinux && atLeast "2.7.13") (patchDir + "/find_library-gcc10.patch")
        # DARWIN ONLY: distutils C++ for Clang
        ++ lib.optional hasDistutilsCxxPatch (
          if older "2.7.17" && atLeast "2.7.6" then
            patchDir + "/distutils-C++.patch"
          else
            patchDir + "/python-2.7-distutils-C++.patch"
        )
        # Cross-compilation
        ++ lib.optional isCross (patchDir + "/cross-compile.patch")
        # macOS entropy fix (needed for < 2.7.13)
        ++ lib.optional (older "2.7.13") (patchDir + "/get-entropy-macos.patch");

      # Compute the fully-controlled patch list for any Python version.
      # This replaces the nixpkgs patch list entirely via overrideAttrs.
      patchesFor =
        {
          version,
          sourceVersion,
          stdenv,
        }:
        let
          mm = "${sourceVersion.major}.${sourceVersion.minor}";
          patchDir = ./patches + "/${mm}";
        in
        if sourceVersion.major == "2" then
          patches2For { inherit version patchDir stdenv; }
        else
          patches3For { inherit version patchDir stdenv; };
    in
    {
      lib.mkPython =
        {
          pkgs,
          version,
          hash,
          url,
          packages,
        }:
        let
          versionList = builtins.splitVersion version;
          versionSuffixList = builtins.concatLists [
            [ "" ]
            (lib.drop 3 versionList)
          ];
          sourceVersion = {
            major = builtins.elemAt versionList 0;
            minor = builtins.elemAt versionList 1;
            patch = builtins.elemAt versionList 2;
            suffix = builtins.concatStringsSep "." versionSuffixList;
          };
          infix = if sourceVersion.major == "2" then "2.7/" else "";

          callPackage = pkgs.newScope {
            inherit python;
            pkgsBuildHost = pkgs.pkgsBuildHost // {
              "python${sourceVersion.major}${sourceVersion.minor}" = python;
            };
          };

          pythonFun = import "${toString pkgs.path}/pkgs/development/interpreters/python/cpython/${infix}default.nix";
          pythonSrc = pkgs.fetchurl {
            inherit url;
            sha256 = hash;
          };
          python =
            (callPackage pythonFun (
              {
                inherit sourceVersion;
                hash = "sha256-${hash}";
                self = packages.${version};
                passthruFun = callPackage "${pkgs.path}/pkgs/development/interpreters/python/passthrufun.nix" { };
              }
              // lib.optionalAttrs (sourceVersion.major == "3") {
                # Dummy — we override patches entirely in overrideAttrs
                noldconfigPatch = ./patches/shared/no-op.patch;
              }
              // lib.optionalAttrs (versionInBetween version "3.5" "3.0" && pkgs.stdenv.isLinux) {
                # Python 3.0-3.4 segfaults with newer GCC on Linux
                stdenv = pkgs.overrideCC pkgs.stdenv pkgs.gcc9;
              }
              // lib.optionalAttrs (lib.functionArgs pythonFun ? configd) {
                # Nixpkgs had a Darwin SDK refactor in 24.11 which removed configd from the Python derivation
                # Only inject configd for older Nixpkgs where it's required.
                inherit (pkgs.darwin) configd;
              }
            )).overrideAttrs
              (old: {
                src = pythonSrc;
                # Fully-controlled patch list — independent of nixpkgs patch management
                patches = patchesFor {
                  inherit version sourceVersion;
                  inherit (pkgs) stdenv;
                };
                # Compatibility with substitutions done by the nixpkgs postPatch
                prePatch =
                  lib.optionalString (versionInBetween version "3.7" "3.0") ''
                    substituteInPlace Lib/subprocess.py --replace-fail '"/bin/sh"' "'/bin/sh'"
                  ''
                  + (old.prePatch or "");
                # Fill in the missing pc file for old Python 3 versions
                postInstall =
                  lib.optionalString (versionInBetween version "3.5.2" "3.0") ''
                    ln -s "$out/lib/pkgconfig/python-${sourceVersion.major}.${sourceVersion.minor}.pc" "$out/lib/pkgconfig/python3.pc"
                  ''
                  + (old.postInstall or "");
                meta = old.meta // {
                  knownVulnerabilities = [ ];
                };
                passthru = old.passthru // {
                  doc = old.passthru.doc.overrideAttrs {
                    src = pythonSrc;
                  };
                };
              });
        in
        python;

      lib.versions = builtins.fromJSON (builtins.readFile ./versions.json);

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          getRelease =
            version: source:
            self.lib.mkPython {
              inherit pkgs version packages;
              inherit (source) hash url;
            };
          getLatest = version: latest: getRelease latest self.lib.versions.releases.${latest};
          packages =
            pkgs.lib.mapAttrs getRelease self.lib.versions.releases
            // pkgs.lib.mapAttrs getLatest self.lib.versions.latest;
        in
        packages
      );

      patchChecks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          patchedPackages = pkgs.lib.mapAttrs (
            name: pkg:
            pkg.overrideAttrs (_: {
              phases = [
                "unpackPhase"
                "patchPhase"
                "installPhase"
              ];
              installPhase = "mkdir -p $out";
              separateDebugInfo = false;
              dontStrip = true;
            })
          ) self.packages.${system};
        in
        patchedPackages
        // {
          all = pkgs.linkFarm "all-patch-checks" (
            lib.mapAttrsToList (name: drv: {
              inherit name;
              path = drv;
            }) patchedPackages
          );
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.lib.concatMapAttrs (
          version: python:
          {
            ${version} = python;
          }
          // lib.optionalAttrs (versionInBetween version "3" "2.7.18") {
            ${version + "-ssl"} = pkgs.runCommand "${version}-test-ssl" { } ''
              set -x

              mkdir $out
              ${python}/bin/python -c 'import ssl; print(ssl.OPENSSL_VERSION)' | tee $out/openssl-version
            '';
          }
          // lib.optionalAttrs (versionInBetween version "3.12" "3.6") {
            ${version + "-ensurepip"} = pkgs.runCommand "${version}-test-ensurepip" { } ''
              set -x

              mkdir $out
              ${python}/bin/python -m ensurepip --help | tee $out/ensurepip-help
            '';
          }
        ) self.packages.${system}
      );
    };
}
