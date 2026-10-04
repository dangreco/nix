{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
  mkHome = modules: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit modules;
  };
in
{
  keys.hosts.sake = { age = "age1p05jfxexuyrq0unt6gpzx8gfx2s47g28h4aushas07suaphpfd4sxjvg06"; opItem = "sake.2026.10.04"; };

  flake.modules.nixos.sake = {
    imports = [ nixos.desktop nixos.dan ];
    networking.hostName = "sake";
    nixpkgs.hostPlatform = "x86_64-linux";
    my.disk.device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R924661P";
    hardware.facter.reportPath = ./facter.json;
    boot.lanzaboote.autoEnrollKeys.includeFirmwareBuiltinKeys = true;
  };

  flake.nixosConfigurations.sake = inputs.nixpkgs.lib.nixosSystem { modules = [ nixos.sake ]; };
  flake.homeConfigurations."dan@sake" = mkHome [ hm.dan hm.onepassword ];
}
