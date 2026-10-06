{ config, self, ... }:
let
  master = config.keys.master;
in
{
  keys.users.work = "age1n9qy2004um4ka960r03vsegmgg6530kx5gh3966nt9z3ky8vg46s37fw7r";

  flake.modules.nixos.work =
    { config, lib, ... }:
    {
      my.users = [ "work" ];

      programs.git.enable = true;
      programs.ssh.knownHosts."github.com".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

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

      home-manager.users.work =
        { config, pkgs, ... }:
        {
          # Features; each also needs the host side on (my.<feature>.enable) to apply.
          my = {
            gnome.enable = true;
            onepassword.enable = true;
            devTools.enable = true;
            zed.enable = true;
            omp.enable = true;
            gitid.enable = true;
          };

          home.packages = [
            pkgs.gh
            pkgs.worktrunk
          ];

          # Extra config from the sops-held git-credentials file and an unmanaged config.local.
          programs.git = {
            enable = true;
            includes = [
              { path = config.sops.secrets."git-credentials".path; }
              { path = "~/.config/git/config.local"; }
            ];
          };

          sops = {
            age.keyFile = "/run/secrets/users/work/age-key";
            defaultSopsFile = self + "/secrets/users/work.yaml";
            secrets."git-credentials" = { };
          };

          dconf.settings."org/gnome/shell" = {
            favorite-apps = lib.mkAfter [ "com.slack.Slack.desktop" ];
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
