{ config, self, ... }:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;
in
{
  keys.users.dan = "age1z623ah3syzzae9lauvukws96w3lsr99tq2a05cc8w7ktnv7mv3lq2sj50p";

  flake.modules.nixos.dan =
    { config, ... }:
    {
      imports = [ nixos.dan-git ];

      my.users = [ "dan" ];

      sops.secrets."users/dan/password" = {
        sopsFile = self + "/secrets/users/dan.yaml";
        neededForUsers = true;
      };
      sops.secrets."users/dan/age-key" = {
        sopsFile = self + "/secrets/users/dan.yaml";
        owner = "dan";
      };

      users.users.dan = {
        isNormalUser = true;
        uid = 1000;
        description = "Dan Greco";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        hashedPasswordFile = config.sops.secrets."users/dan/password".path;
        openssh.authorizedKeys.keys = [ master ];
      };

      environment.persistence."/persist".users.dan.directories = [
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Videos"
        "projects"
        {
          directory = ".ssh";
          mode = "0700";
        }
      ];
    };
}
