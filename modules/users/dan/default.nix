{ config, self, ... }:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;

  git = {
    name = "Dan Greco";
    email = "git@dangre.co";
  };
in
{
  keys.users.dan = "age1z623ah3syzzae9lauvukws96w3lsr99tq2a05cc8w7ktnv7mv3lq2sj50p";

  # System-wide git identity and GitHub host key; also used by the installer ISO.
  flake.modules.nixos.dan-git = {
    programs.git = {
      enable = true;
      config.user = git;
    };
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  flake.modules.nixos.dan =
    { config, ... }:
    {
      imports = [ nixos.dan-git ];

      my.users = [ "dan" ];
      my.githubUsers.dan = "dangreco";

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

      home-manager.users.dan = {
        # Features; each also needs the host side on (my.<feature>.enable) to apply.
        my = {
          gnome.enable = true;
          onepassword.enable = true;
          devTools.enable = true;
          zed.enable = true;
          omp.enable = true;
        };

        programs.git = {
          enable = true;
          settings.user = git;
        };

        sops = {
          age.keyFile = "/run/secrets/users/dan/age-key";
          defaultSopsFile = self + "/secrets/users/dan.yaml";
          secrets."users/dan/home/smoke" = { };
        };

        home.persistence."/persist".directories = [
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
    };
}
