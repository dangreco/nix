{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  # Git worktrees are managed with worktrunk (`wt`) for every user on every host:
  #  - worktrees live in <repo>/.worktrees/<branch>, from the system config
  #    /etc/xdg/worktrunk/config.toml (a user's ~/.config/worktrunk/config.toml
  #    is layered over it);
  #  - creating a worktree fetches and runs `wt step prune` in the background,
  #    which removes clean worktrees older than an hour whose changes are already
  #    in the remote default branch (squash merges included); dirty ones are kept;
  #  - `.worktrees/` is ignored by every repository through /etc/gitconfig.
  #    core.excludesFile replaces git's default ~/.config/git/ignore, so a
  #    per-user ignore file (Home Manager programs.git.ignores) would have to
  #    repeat `.worktrees/`.
  # omp agents are told to use wt by the rule in ../ai/omp.
  flake.modules.nixos.worktrees =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.worktrunk ];

      programs.git = {
        enable = true;
        config.core.excludesFile = "${pkgs.writeText "gitignore" ".worktrees/\n"}";
      };

      environment.etc."xdg/worktrunk/config.toml".source =
        (pkgs.formats.toml { }).generate "worktrunk.toml"
          {
            worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}";
            # Offline, prune still runs against the last fetched default branch.
            post-start.prune = "${lib.getExe pkgs.git} fetch --quiet --prune || true; ${lib.getExe pkgs.worktrunk} step prune --yes";
          };
    };

  flake.modules.nixos.base.imports = [ nixos.worktrees ];
}
