{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  opItem = config.keys.hosts.sake.opItem;
in
{
  keys.hosts.sake = {
    age = "age1p05jfxexuyrq0unt6gpzx8gfx2s47g28h4aushas07suaphpfd4sxjvg06";
    opItem = "sake.2026.10.04";
  };

  flake.modules.nixos.sake = {
    imports = [
      nixos.base
      nixos.dan
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen
    ];

    my.profiles.desktop.enable = true;
    my.hibernate.enable = true;

    networking.hostName = "sake";
    nixpkgs.hostPlatform = "x86_64-linux";
    my.disk.device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R924661P";
    my.disk.swapSize = "32G";
    hardware.facter.reportPath = ./facter.json;

    # This firmware has no dbDefault EFI variable, so `sbctl enroll-keys
    # --firmware-builtin` always fails here (includeFirmwareBuiltinKeys stays off).
    # Microsoft keys are still enrolled (the lanzaboote default), which covers option ROMs.

    # Alder Lake only needs the iHD driver; the nixos-hardware profile pulls in both.
    hardware.intelgpu.vaapiDriver = "intel-media-driver";

    # UEFI and Thunderbolt firmware from LVFS.
    services.fwupd.enable = true;
    services.thermald.enable = true;

    home-manager.users.dan.my.onepassword.sshAgentItems = [ opItem ];
  };

  flake.nixosConfigurations.sake = inputs.nixpkgs.lib.nixosSystem { modules = [ nixos.sake ]; };
}
