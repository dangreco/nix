# nix

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
