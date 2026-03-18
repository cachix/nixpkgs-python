"""Sync vendored patches from nixpkgs using Nix evaluation.

Run on both Linux and Darwin to catch platform-conditional patches.
CI should run this on at least one Linux and one Darwin runner.

Usage:
    python -m scripts.sync_patches
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

# Only check versions that nixpkgs still supports.
# When nixpkgs drops a version, its patches are frozen — no sync needed.
SUPPORTED_VERSIONS = ["3.11", "3.12", "3.13", "3.14", "3.15"]

# Known NixOS-specific patches that we vendor.
# New upstream patches not in this set are flagged for human review.
KNOWN_PATCHES = {
    "no-ldconfig.patch",
    "mimetypes.patch",
    "virtualenv-permissions.patch",
    "python-3.x-distutils-C++.patch",
    "0001-On-all-posix-systems-not-just-Darwin-set-LDSHARED-if.patch",
    "fix-finding-headers-when-cross-compiling.patch",
    "loongarch-support.patch",
    "platform-triplet-detection.patch",
    "freebsd-cross.patch",
}

# CVE patches we deliberately exclude
CVE_PATTERN = "CVE-"


def get_system() -> str:
    result = subprocess.run(
        ["nix", "eval", "--raw", "--impure", "--expr", "builtins.currentSystem"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def build_upstream_patches(version: str, system: str) -> Path | None:
    """Build the unmodified nixpkgs CPython derivation and extract its patch list."""
    expr = f"""
    let
      pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.{system};
      cpythonFun = import "${{pkgs.path}}/pkgs/development/interpreters/python/cpython/default.nix";
      sv = {{ major = "3"; minor = "{version.split('.')[1]}"; patch = "0"; suffix = ""; }};
      drv = pkgs.callPackage cpythonFun {{
        sourceVersion = sv;
        hash = pkgs.lib.fakeHash;
        self = drv;
        passthruFun = pkgs.callPackage
          "${{pkgs.path}}/pkgs/development/interpreters/python/passthrufun.nix" {{}};
      }};
      collectPatches = pkgs.runCommand "upstream-patches-{version}" {{}} ''
        mkdir -p $out
        ${{pkgs.lib.concatImapStringsSep "\\n" (i: p: ''
          cp ${{p}} $out/${{toString i}}-$(basename ${{p}})
        '') drv.patches}}
      '';
    in collectPatches
    """
    try:
        result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr", expr],
            capture_output=True,
            text=True,
            check=True,
        )
        return Path(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        print(f"  SKIP {version}: evaluation failed ({e.stderr.strip()[:100]})")
        return None


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_patches(
    upstream_dir: Path, vendor_dir: Path, system: str
) -> list[str]:
    """Compare upstream patch content against vendored patches."""
    changes: list[str] = []
    platform = "darwin" if "darwin" in system else "linux"

    upstream_patches: dict[str, Path] = {}
    for f in sorted(upstream_dir.iterdir()):
        # Strip numeric prefix: "1-mimetypes.patch" -> "mimetypes.patch"
        name = f.name.split("-", 1)[1] if "-" in f.name else f.name
        upstream_patches[name] = f

    for name, upstream_path in upstream_patches.items():
        # Skip CVE patches — we deliberately exclude them
        if CVE_PATTERN in name:
            continue

        if name not in KNOWN_PATCHES:
            changes.append(f"NEW ({platform}): {name} — review if NixOS-specific or backport")
        else:
            # Check if content changed vs our vendored copy
            # Our vendored patches are in shared/ or version dirs, find by name
            candidates = list(vendor_dir.rglob(name))
            if not candidates:
                changes.append(f"MISSING ({platform}): {name} — not vendored")
            else:
                for candidate in candidates:
                    if file_hash(upstream_path) != file_hash(candidate):
                        changes.append(
                            f"CHANGED ({platform}): {name} "
                            f"(upstream vs {candidate.relative_to(vendor_dir)})"
                        )

    return changes


def sync() -> dict[str, tuple[list[str], Path]]:
    system = get_system()
    platform = "darwin" if "darwin" in system else "linux"
    patches_dir = Path("patches")
    all_changes: dict[str, tuple[list[str], Path]] = {}

    print(f"Running patch sync on {system} ({platform})")

    for version in SUPPORTED_VERSIONS:
        print(f"  Checking {version}...")
        upstream_dir = build_upstream_patches(version, system)
        if upstream_dir is None:
            continue

        changes = compare_patches(upstream_dir, patches_dir, system)
        if changes:
            all_changes[version] = (changes, upstream_dir)

    return all_changes


def main() -> None:
    all_changes = sync()
    if all_changes:
        print("\nPatch differences detected:")
        for version, (changes, _) in all_changes.items():
            print(f"\n  {version}:")
            for c in changes:
                print(f"    {c}")
        print("\nReview and update vendored patches.")
        print("Note: run on BOTH Linux and Darwin for full coverage.")
        sys.exit(1)
    else:
        print("\nAll vendored patches match upstream nixpkgs on this platform.")


if __name__ == "__main__":
    main()
