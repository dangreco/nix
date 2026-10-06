{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
  mkHome =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      inherit modules;
    };
in
{
  keys.hosts.mezcal = {
    age = "age1m2vunnkxep23camfmzgv0qvtp6dttx3822wv8mkc2cedegqzvu3qge46mv";
    opItem = "mezcal.2026.10.03";
  };

  flake.modules.nixos.mezcal = {
    imports = [
      nixos.desktop
      nixos.dan
      nixos.work
      inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    ];

    networking.hostName = "mezcal";
    nixpkgs.hostPlatform = "x86_64-linux";
    my.disk.device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76878C3509";
    my.disk.swapSize = "32G";
    hardware.facter.reportPath = ./facter.json;
    hardware.framework.enableKmod = true;
    boot.kernelModules = [
      "cros_ec_lpcs"
      "cros_ec_hwmon"
    ];

    # Framework: keep vendor-signed firmware updates working.
    boot.lanzaboote.autoEnrollKeys.includeFirmwareBuiltinKeys = true;
  };

  flake.nixosConfigurations.mezcal = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.mezcal ];
  };

  flake.homeConfigurations."dan@mezcal" = mkHome [
    hm.dan
    hm.desktop
    { my.onepassword.sshAgentItems = [ config.keys.hosts.mezcal.opItem ]; }
  ];

  flake.homeConfigurations."work@mezcal" = mkHome [
    hm.work
    hm.desktop
    { my.onepassword.sshAgentItems = [ ]; }
  ];
}
