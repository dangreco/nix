_: {
  # fish is the login shell for every user on every host. The default greeting is
  # turned off system-wide; `set -g fish_greeting` in ~/.config/fish brings it back
  # or changes the text.
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;
        # Translate the NixOS environment (NIX_PATH, profiles, ...) into native fish.
        useBabelfish = true;
        interactiveShellInit = ''
          set -g fish_greeting
        '';
      };

      users.defaultUserShell = pkgs.fish;

      # Upstream installers (zed, omp) put their CLIs in ~/.local/bin. Set in the PAM
      # environment so the systemd user manager, GUI apps and every shell inherit it.
      # home.sessionPath is not enough: hm-session-vars is skipped when
      # __HM_SESS_VARS_SOURCED leaks in from the systemd user env, and
      # environment.localBinInPath when fish inherits __fish_nixos_env_preinit_sourced.
      environment.sessionVariables.PATH = [ "$HOME/.local/bin" ];

      # Command history. Universal variables (~/.config/fish/fish_variables) are not
      # persisted: set options in the Home Manager config instead.
      home-manager.sharedModules = [
        { home.persistence."/persist".directories = [ ".local/share/fish" ]; }
      ];
    };
}
