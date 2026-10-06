_: {
  # Caffeine: top-bar toggle that inhibits suspend and the screensaver.
  # Settings schema: org.gnome.shell.extensions.caffeine (dconf path below).
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Only where the user has GNOME on (see ../default.nix).
    lib.mkIf config.programs.gnome-shell.enable {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.caffeine; } ];
      dconf.settings."org/gnome/shell/extensions/caffeine" = {
        # Keep the toggle's on/off state across logins.
        restore-state = true;
        # Always show the top-bar icon, not only while caffeine is active.
        show-indicator = "always";
      };
    };
}
