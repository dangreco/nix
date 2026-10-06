{ inputs, ... }:
{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      options.my.secureBoot.enable = lib.mkEnableOption "Secure Boot through lanzaboote";

      config = lib.mkIf config.my.secureBoot.enable {
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
    };
}
