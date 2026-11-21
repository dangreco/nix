# nix

[![CI](https://github.com/dangreco/nix/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/dangreco/nix/actions/workflows/ci.yml)
[![Flake updates](https://github.com/dangreco/nix/actions/workflows/update-flake-lock.yml/badge.svg?branch=dev)](https://github.com/dangreco/nix/actions/workflows/update-flake-lock.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](flake.nix)

Personal NixOS and Home Manager configuration.

- `modules/hosts/` — host configurations.
- `modules/` — shared system and user modules.
- `secrets/` — SOPS-encrypted secrets.

```sh
nix develop
nix fmt
nix flake check
```

Flake inputs update nightly and merge automatically after CI passes.
