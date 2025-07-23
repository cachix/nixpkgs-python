{ pkgs, ... }:
{
  packages = [
    pkgs.jq
    pkgs.nix-fast-build
  ];

  git-hooks.hooks = {
    nixfmt-rfc-style.enable = true;
    prettier = {
      enable = true;
      excludes = [ "versions.json" ];
    };
    shellcheck.enable = true;
    shfmt = {
      enable = true;
      after = [ "shellcheck" ];
    };
  };
}
