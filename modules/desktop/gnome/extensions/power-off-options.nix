_: {
  # Power Off Options: adds Hibernate to GNOME's power-off dialog (calls logind Hibernate).
  # Settings schema: org.gnome.shell.extensions.power-off-options.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Only where the user has GNOME on (see ../default.nix).
    lib.mkIf config.programs.gnome-shell.enable {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.power-off-options; } ];
      dconf.settings."org/gnome/shell/extensions/power-off-options".show-hibernate = true;
    };
}
