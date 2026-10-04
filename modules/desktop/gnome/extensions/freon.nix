_: {
  # Freon: CPU, disk and GPU temperatures, voltages and fan speeds in the top bar.
  flake.modules.homeManager.gnome =
    { pkgs, ... }:
    {
      programs.gnome-shell.extensions = [ { package = pkgs.gnomeExtensions.freon; } ];
    };
}
