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
    nixos.boot-splash
    nixos.sops
    nixos.network-connections
    nixos.gnome
    nixos.github-avatar
    nixos.firefox
    nixos.firefox-gnome-theme
    nixos.onepassword
    nixos.flatpak
    nixos.flatpak-apps
    nixos.podman
    nixos.dev-tools
    nixos.zed
    nixos.microcontrollers
  ];
}
