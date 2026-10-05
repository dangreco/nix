{ config, self, ... }:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;
in
{
  keys.users.work = "age1n9qy2004um4ka960r03vsegmgg6530kx5gh3966nt9z3ky8vg46s37fw7r";

  flake.modules.nixos.work =
    { config, ... }:
    {
      imports = [ nixos.work-git ];

      my.users = [ "work" ];

      sops.secrets."users/work/password" = {
        sopsFile = self + "/secrets/users/work.yaml";
        neededForUsers = true;
      };
      sops.secrets."users/work/age-key" = {
        sopsFile = self + "/secrets/users/work.yaml";
        owner = "work";
      };

      users.users.work = {
        isNormalUser = true;
        uid = 1001;
        description = "Work";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        hashedPasswordFile = config.sops.secrets."users/work/password".path;
        openssh.authorizedKeys.keys = [ master ];
      };

      environment.persistence."/persist".users.work.directories = [
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
