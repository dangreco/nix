{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  flake.modules.nixos.desktop.imports = [
    nixos.base
    nixos.disk
    nixos.impermanence
    nixos.secure-boot
    nixos.sops
    nixos.network-connections
    nixos.gnome
    nixos.onepassword
    nixos.flatpak
    nixos.podman
  ];
}
