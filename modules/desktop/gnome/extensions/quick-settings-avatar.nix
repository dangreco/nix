_: {
  # Quick Settings Avatar: shows the user's avatar in the Quick Settings menu.
  flake.modules.homeManager.gnome =
    { pkgs, ... }:
    {
      programs.gnome-shell.extensions = [
        { package = pkgs.gnomeExtensions.user-avatar-in-quick-settings; }
      ];
    };
}
