{ pkgs, ... }: {
  languages.python.enable = true;
  languages.python.venv.enable = true;

  packages = [ pkgs.jq ];

  enterShell = ''
    pip install requests
  '';
}