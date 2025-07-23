{ pkgs, ... }:
{
  languages.python = {
    enable = true;
    venv.enable = true;
    uv = {
      enable = true;
      sync.enable = true;
    };
  };

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
    ruff-format = {
      enable = true;
      after = [ "ruff" ];
    };
  };
}
