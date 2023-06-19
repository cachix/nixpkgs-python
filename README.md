# nixpkgs-python

All Python versions, kept up-to-date on hourly basis using Nix.

## Supported Python Versions

This project supports the following Python versions:

- 2.7.6+
- 3.3.1+ (up to the latest release)

## Cachix (optional)

If you'd like to avoid compilation [install Cachix](https://docs.cachix.org/installation) and:

    $ cachix use nixpkgs-python

Using the following platforms:

- x86_64-darwin
- x86_64-linux
- aarch64-linux
- aarch64-darwin

## Usage

### ad-hoc

You can run this package ad-hoc using the following command:

    $ nix shell github:cachix/nixpkgs-python#'"2.7"'

Or specify a minor version:

    $ nix shell github:cachix/nixpkgs-python#'"2.7.16"'

### [devenv.sh](https://devenv.sh)

Create `devenv.nix`:

```nix
{ pkgs, ... }: 

{
  languages.python.enable = true;
  languages.python.version = "3.11";
  # languages.python.version = "3.11.3";
}
```

Create `devenv.yaml`:

```yaml
inputs:
  nixpkgs-python:
    url: github:cachix/nixpkgs-python
```

Then run:

    $ devenv shell
    ...

### flake.nix

```nix
{
  inputs = {
    nixpkgs-python.url = "github:cachix/nixpkgs-python";
  };

  outputs = { self, nixpkgs-python }: {
    # You can now refer to packages like:
    #   nixpkgs-python.packages.x86_64-linux."2.7"
  };
}
```
