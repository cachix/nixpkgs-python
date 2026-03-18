{ pkgs, config, ... }:
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

  scripts.nixpkgs-python-check.exec = ''
    python -m scripts.check_with_summary "$@"
  '';
  scripts.nixpkgs-python-summary.exec = ''
    python -m scripts.json_to_summary "$@"
  '';
  scripts.nixpkgs-python-update.exec = ''
    python -m scripts.update "$@"
  '';
  scripts.nixpkgs-python-sync-patches.exec = ''
    python -m scripts.sync_patches "$@"
  '';

  git-hooks.hooks = {
    nixfmt.enable = true;
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
