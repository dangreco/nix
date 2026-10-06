_: {
  # Quick Settings Avatar: shows the user's avatar in the Quick Settings menu.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Only where the user has GNOME on (see ../default.nix).
    lib.mkIf config.programs.gnome-shell.enable {
      programs.gnome-shell.extensions = [
        { package = pkgs.gnomeExtensions.user-avatar-in-quick-settings; }
      ];
    };
}
