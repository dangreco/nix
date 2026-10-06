_: {
  # Everyday command-line tools for development. Picked from the common "modern unix"
  # lists (ripgrep, fd, bat, eza, fzf, zoxide, delta, lazygit, jq, ...). Tools with a Home
  # Manager module are configured through it; the rest are plain packages.
  # User-only: home-manager.users.<name>.my.devTools.enable.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.devTools.enable = lib.mkEnableOption "everyday command-line development tools";

      config = lib.mkIf config.my.devTools.enable {
        # The NixOS side makes fish the login shell, but Home Manager only writes the shell
        # integrations of the programs below when its own fish module is on.
        programs.fish.enable = true;

        programs = {
          ripgrep.enable = true;
          fd.enable = true;
          bat.enable = true;
          jq.enable = true;
          btop.enable = true;
          lazygit.enable = true;

          eza = {
            enable = true;
            git = true;
          };

          fzf = {
            enable = true;
            # fd honours .gitignore and is much faster than the default find.
            defaultCommand = "fd --type f --hidden --exclude .git";
            fileWidgetCommand = "fd --type f --hidden --exclude .git";
            changeDirWidgetCommand = "fd --type d --hidden --exclude .git";
          };

          zoxide.enable = true;

          direnv = {
            enable = true;
            # Caches `use flake` so entering a project does not re-evaluate every time.
            nix-direnv.enable = true;
          };

          delta = {
            enable = true;
            enableGitIntegration = true;
          };

          tealdeer = {
            enable = true;
            # Fetch the pages on first use; the cache is persisted below.
            settings.updates.auto_update = true;
          };
        };

        home.packages = with pkgs; [
          tree
          yq-go
          hyperfine
          dust
          duf
          procs
          xh
        ];

        # State the tools build up over time.
        home.persistence."/persist".directories = [
          ".local/share/zoxide" # learned directory ranking
          ".local/share/direnv" # which .envrc files are allowed
          ".cache/tealdeer" # downloaded tldr pages
        ];
      };
    };
}
