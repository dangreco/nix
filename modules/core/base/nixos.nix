{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  # Every host imports base, so everything imported here is on every host.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      imports = [
        nixos.shell
        nixos.update
      ];

      options.my.users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Normal users this flake manages on the host.";
      };

      config = {
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          use-xdg-base-directories = true;
        };
        nixpkgs.config.allowUnfree = true;

        networking.networkmanager.enable = true;

        time.timeZone = "America/Toronto";
        i18n.defaultLocale = "en_CA.UTF-8";
        console.keyMap = "us";

        users.mutableUsers = false;
        zramSwap.enable = true;

        environment.systemPackages = [ pkgs.git ];

        system.stateVersion = "26.05";
      };
    };
}
