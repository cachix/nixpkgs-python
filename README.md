# nixpkgs-python

All Python versions, kept up-to-date on hourly basis using Nix.

## Supported Python Versions

This project supports the following Python versions:

- 2.7.6+
- 3.3.1+ (up to the latest release)

## Caching (optional)

Use the [Cachix](https://docs.cachix.org/installation) binary cache to avoid rebuilding Python from source.

#### System-wide

[Install Cachix](https://docs.cachix.org/installation) and run:

    $ cachix use nixpkgs-python

#### devenv

Add to your `devenv.nix`:

```nix
cachix.pull = [ "nixpkgs-python" ];
```

#### Flake

Add the cache substituter and public key to your `flake.nix`:

```nix
{
  nixConfig = {
    extra-substituters = "https://nixpkgs-python.cachix.org";
    extra-trusted-public-keys = "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=";
  };
}
```

> [!NOTE]
> Do not override the `nixpkgs` input when using this flake.
> The cached builds are tied to the pinned nixpkgs revision; overriding it will result in cache misses and local rebuilds.

To push your own builds to the cache (useful in CI or team setups), [create a Cachix account](https://app.cachix.org/) and configure a push workflow so builds are cached as they happen.

Supported platforms:

- x86_64-darwin
- x86_64-linux
- aarch64-linux
- aarch64-darwin

## Usage

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

### nix shell

You can run this package ad-hoc using the following command:

    $ nix shell github:cachix/nixpkgs-python#'"2.7"'

Or specify a minor version:

    $ nix shell github:cachix/nixpkgs-python#'"2.7.16"'
