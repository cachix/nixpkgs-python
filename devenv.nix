{ pkgs, ... }:
{
  languages.python.enable = true;

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
    ruff.enable = true;
    ruff-format.enable = true;
    shellcheck.enable = true;
    shfmt = {
      enable = true;
      after = [ "shellcheck" ];
    };
  };
}
