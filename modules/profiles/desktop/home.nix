{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  # Home Manager side of the desktop profile; hosts import nixos.desktop and this.
  flake.modules.homeManager.desktop.imports = [
    hm.gnome
    hm.onepassword
    hm.dev-tools
  ];
}
