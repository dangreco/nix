_: {
  # Power Off Options: adds Hibernate to GNOME's power-off dialog (calls logind Hibernate).
  # Settings schema: org.gnome.shell.extensions.power-off-options.
  flake.modules.homeManager.gnome =
    { pkgs, ... }:
    {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.power-off-options; } ];
      dconf.settings."org/gnome/shell/extensions/power-off-options".show-hibernate = true;
    };
}
