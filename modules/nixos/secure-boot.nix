{ inputs, ... }:
{
  flake.modules.nixos.secure-boot =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.systemd-boot.configurationLimit = 10;
      boot.loader.efi.canTouchEfiVariables = true;

      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        autoGenerateKeys.enable = true;
        autoEnrollKeys = {
          enable = true;
          autoReboot = true;
        };
      };

      environment.systemPackages = [ pkgs.sbctl ];
      environment.persistence."/persist".directories = [ "/var/lib/sbctl" ];
    };
}
