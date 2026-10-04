_: {
  # Caffeine: top-bar toggle that inhibits suspend and the screensaver.
  # Settings schema: org.gnome.shell.extensions.caffeine (dconf path below).
  flake.modules.homeManager.gnome =
    { pkgs, ... }:
    {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.caffeine; } ];
      dconf.settings."org/gnome/shell/extensions/caffeine" = { };
    };
}
