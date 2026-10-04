_: {
  # TopHat: CPU, memory, disk and network activity in the top bar.
  flake.modules.homeManager.gnome =
    { pkgs, ... }:
    {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.tophat; } ];
    };
}
