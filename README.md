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

PR CI evaluates every host and check, then builds only the light checks (~2 min).
Host closures and NixOS tests are built in full by the nightly flake update, or
on demand by running the CI workflow with `full`.
Flake inputs update nightly and merge automatically after the full build passes.

Changes to `dev` require an up-to-date PR, passing CI, and resolved review threads;
no reviewer approval is required. Squash/rebase merges only; no force-pushes,
deletion, or bypass actors. [Ruleset configuration](.github/rulesets/dev.json).
