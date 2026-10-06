_: {
  # Freon: CPU, disk and GPU temperatures, voltages and fan speeds in the top bar.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Only where the user has GNOME on (see ../default.nix).
    lib.mkIf config.programs.gnome-shell.enable {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.freon; } ];
    };
}
