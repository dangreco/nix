# nix

[![CI](https://github.com/dangreco/nix/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/dangreco/nix/actions/workflows/ci.yml)
[![Flake updates](https://github.com/dangreco/nix/actions/workflows/update-flake-lock.yml/badge.svg?branch=dev)](https://github.com/dangreco/nix/actions/workflows/update-flake-lock.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](flake.nix)
[![Release](https://img.shields.io/github/v/release/dangreco/nix?label=release)](https://github.com/dangreco/nix/releases)

Personal NixOS and Home Manager configuration.

- `modules/hosts/` — host configurations.
- `modules/` — shared system and user modules.
- `secrets/` — SOPS-encrypted secrets.

```sh
nix develop
nix fmt
nix flake check
```

PR CI evaluates every host and check, then builds only the light checks (~1 min).
Host closures and NixOS tests are built in full by the nightly flake update, or
on demand by running the CI workflow with `full`.
Flake inputs update nightly and merge automatically after the full build passes.

## Releases

Hosts run `main`; development happens on `dev`. Every Sunday at 08:00 UTC, the
[Release workflow](.github/workflows/release.yml) cuts `dev` into a PR to `main`
named after the date (CalVer `YYYY.MM.DD`; a second release the same day is
`YYYY.MM.DD.1`, then `.2`). The PR body is the changelog, grouped by conventional
commit type. Once the full build passes, the PR is merged with a merge commit,
which is tagged and published as a GitHub Release. Nothing new on `dev`: no release.

For an urgent fix, merge it to `dev`, then run the Release workflow manually.

```sh
update          # apply the latest release from main
update --local  # apply ~/projects/dangreco/nix instead, e.g. to test dev
```

New installs clone `main`. The installer pushes the new host's config to an
`install/*` branch and opens a PR into `dev`; until it is released, use
`update --local` on that host.

## Branch protection

Changes to `dev` require an up-to-date PR, passing CI, and resolved review threads;
no reviewer approval is required. Squash/rebase merges only; no force-pushes,
deletion, or bypass actors. `main` accepts only release PRs merged with a merge
commit after the full build (`Release / Full checks`). No force-pushes, deletion,
or bypass actors on either. Rulesets: [dev](.github/rulesets/dev.json),
[main](.github/rulesets/main.json).
