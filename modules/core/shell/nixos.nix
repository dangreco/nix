_: {
  # fish is the login shell for every user on every host. The default greeting is
  # turned off system-wide; `set -g fish_greeting` in ~/.config/fish brings it back
  # or changes the text.
  flake.modules.nixos.shell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

      # Command history. Universal variables (~/.config/fish/fish_variables) are not
      # persisted: set options in the Home Manager config instead.
      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [ ".local/share/fish" ];
      });
    };
}
