{ config, self, ... }:
let
  master = config.keys.master;

  git = {
    name = "Dan Greco";
    email = "git@dangre.co";
  };

  githubHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
in
{
  keys.users.dan = "age1z623ah3syzzae9lauvukws96w3lsr99tq2a05cc8w7ktnv7mv3lq2sj50p";

  # System-wide git identity and GitHub host key for the installer ISO, where root is
  # the only user. Not imported by `dan`: /etc/gitconfig is every user's fallback, so
  # it would author other users' (work's) commits as dan; dan's identity is set in his
  # own Home Manager config below.
  flake.modules.nixos.dan-git = {
    programs.git = {
      enable = true;
      config.user = git;
    };
    programs.ssh.knownHosts."github.com".publicKey = githubHostKey;
  };

  flake.modules.nixos.dan =
    { config, ... }:
    {
      programs.git.enable = true;
      programs.ssh.knownHosts."github.com".publicKey = githubHostKey;

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

      home-manager.users.dan = _: {
        # Features; each also needs the host side on (my.<feature>.enable) to apply.
        my = {
          gnome.enable = true;
          onepassword.enable = true;
          devTools.enable = true;
          zed.enable = true;
          croc.enable = true;
          omp.enable = true;
        };

        my.omp.llm = {
          enable = true;
          apiKeySecret = "users/dan/home/omp/llm-api-key";
        };

        programs.git = {
          enable = true;
          settings = {
            user = git // {
              signingkey = "key::${master}";
            };
            gpg = {
              format = "ssh";
              ssh.program = "/run/current-system/sw/bin/op-ssh-sign";
            };
            commit.gpgsign = true;
            tag.gpgsign = true;
          };
        };

        sops = {
          age.keyFile = "/run/secrets/users/dan/age-key";
          defaultSopsFile = self + "/secrets/users/dan.yaml";
          secrets = {
            "users/dan/home/smoke" = { };
          };
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
